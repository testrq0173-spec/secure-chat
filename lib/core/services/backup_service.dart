// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/local/database_service.dart';
import '../../data/models/profile.dart';
import '../crypto/crypto_engine.dart';
import '../crypto/crypto_utils.dart';
import '../storage/secure_storage_service.dart';

class BackupFileInfo {
  final String path;
  final String fileName;
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isDefaultDirectory;

  const BackupFileInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAt,
    this.isDefaultDirectory = false,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    return DateFormat('dd MMM yyyy, hh:mm a').format(modifiedAt);
  }
}

class BackupService {
  final DatabaseService _databaseService;
  final SecureStorageService _secureStorage;

  static const String _magicHeader = 'BHAROSA_BACKUP_V1\n';

  BackupService({
    required DatabaseService databaseService,
    required SecureStorageService secureStorage,
  })  : _databaseService = databaseService,
        _secureStorage = secureStorage;

  /// Gets the primary directory where Bharosa backups are stored
  Future<Directory> getBackupDirectory() async {
    Directory targetDir;
    if (!kIsWeb && Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download/Bharosa_Backups');
      if (await downloadDir.exists()) {
        return downloadDir;
      }
      try {
        await downloadDir.create(recursive: true);
        return downloadDir;
      } catch (_) {
        // Fallback to app documents
        final doc = await getApplicationDocumentsDirectory();
        targetDir = Directory(p.join(doc.path, 'Bharosa_Backups'));
      }
    } else {
      final doc = await getApplicationDocumentsDirectory();
      targetDir = Directory(p.join(doc.path, 'Bharosa_Backups'));
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }

  /// Exports an AES/ChaCha20-Poly1305 encrypted backup to storage
  Future<File> exportEncryptedBackup({
    required String passphrase,
  }) async {
    if (passphrase.trim().isEmpty) {
      throw const FormatException('Backup passphrase cannot be empty');
    }

    // 1. Gather all local database tables
    final dbData = await _databaseService.exportAllData();

    // 2. Gather key material
    final privKey = await _secureStorage.getIdentityPrivateKey();
    final pubKey = await _secureStorage.getIdentityPublicKey();
    final phrase = await _secureStorage.getRecoveryPhrase();
    final activeProfileId = await _secureStorage.getActiveProfileId();

    if (privKey == null || pubKey == null) {
      throw StateError('No identity keys found to back up');
    }

    // 3. Assemble JSON payload
    final payloadMap = {
      'version': 1,
      'app': 'Bharosa Messenger',
      'exportedAt': DateTime.now().toIso8601String(),
      'activeProfileId': activeProfileId,
      'identityPrivateKey': base64Encode(privKey),
      'identityPublicKey': base64Encode(pubKey),
      'recoveryPhrase': phrase,
      'database': dbData,
    };

    final rawJsonBytes = utf8.encode(jsonEncode(payloadMap));

    // 4. Derive 256-bit symmetric encryption key from passphrase using HKDF
    final salt = CryptoUtils.randomBytes(16);
    final symKey = CryptoUtils.hkdf(
      ikm: utf8.encode(passphrase.trim()),
      salt: salt,
      info: utf8.encode('BHAROSA_ENCRYPTED_BACKUP_KEY'),
      length: 32,
    );

    // 5. Encrypt with ChaCha20-Poly1305 AEAD
    final ciphertextWithTag = await CryptoEngine.encryptAead(
      plaintext: rawJsonBytes,
      symmetricKey: symKey,
    );

    // 6. Structure output file: Magic Header + Salt (16B) + Ciphertext (Nonce + Data + Tag)
    final headerBytes = utf8.encode(_magicHeader);
    final totalBytes = Uint8List(headerBytes.length + salt.length + ciphertextWithTag.length);
    totalBytes.setRange(0, headerBytes.length, headerBytes);
    totalBytes.setRange(headerBytes.length, headerBytes.length + salt.length, salt);
    totalBytes.setRange(headerBytes.length + salt.length, totalBytes.length, ciphertextWithTag);

    // 7. Save file to disk
    final backupDir = await getBackupDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'bharosa_backup_$timestamp.enc';
    final file = File(p.join(backupDir.path, fileName));
    await file.writeAsBytes(totalBytes, flush: true);

    return file;
  }

  /// Intelligent Discovery Algorithm:
  /// Auto-scans device storage (Downloads, Bharosa_Backups, Documents) for existing backups
  Future<List<BackupFileInfo>> scanForLocalBackups() async {
    final results = <BackupFileInfo>[];
    final scannedPaths = <String>{};

    final candidateDirs = <Directory>[];

    // Android standard Downloads directory
    if (!kIsWeb && Platform.isAndroid) {
      candidateDirs.add(Directory('/storage/emulated/0/Download/Bharosa_Backups'));
      candidateDirs.add(Directory('/storage/emulated/0/Download'));
    }

    // App Documents directory
    try {
      final docDir = await getApplicationDocumentsDirectory();
      candidateDirs.add(Directory(p.join(docDir.path, 'Bharosa_Backups')));
      candidateDirs.add(docDir);
    } catch (_) {}

    // External Storage
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        candidateDirs.add(Directory(p.join(ext.path, 'Bharosa_Backups')));
        candidateDirs.add(ext);
      }
    } catch (_) {}

    for (final dir in candidateDirs) {
      try {
        if (!await dir.exists()) continue;
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;
          if (scannedPaths.contains(entity.path)) continue;

          final name = p.basename(entity.path);
          final isCandidateName = name.startsWith('bharosa_backup') ||
              name.endsWith('.enc') ||
              name.endsWith('.bharosa_backup') ||
              name.endsWith('.bharosa');

          if (!isCandidateName) continue;

          // Quick inspect header (first 18 bytes)
          try {
            final len = await entity.length();
            if (len < 64) continue; // Minimum header + salt + nonce + mac

            final raf = await entity.open();
            final headerBytes = await raf.read(utf8.encode(_magicHeader).length);
            await raf.close();

            final headerStr = utf8.decode(headerBytes, allowMalformed: true);
            if (headerStr == _magicHeader) {
              final stat = await entity.stat();
              scannedPaths.add(entity.path);
              results.add(
                BackupFileInfo(
                  path: entity.path,
                  fileName: name,
                  sizeBytes: len,
                  modifiedAt: stat.modified,
                  isDefaultDirectory: entity.path.contains('Bharosa_Backups'),
                ),
              );
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Sort newest backups first
    results.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return results;
  }

  /// Restores all user data, identity keys, and chats from an encrypted backup file
  Future<Profile> restoreEncryptedBackup({
    required File backupFile,
    required String passphrase,
  }) async {
    if (!await backupFile.exists()) {
      throw const FileSystemException('Backup file does not exist');
    }

    final bytes = await backupFile.readAsBytes();
    final headerBytes = utf8.encode(_magicHeader);

    if (bytes.length < headerBytes.length + 16 + 28) {
      throw const FormatException('Corrupted backup file: insufficient size');
    }

    // Verify magic header
    final fileHeader = utf8.decode(bytes.sublist(0, headerBytes.length), allowMalformed: true);
    if (fileHeader != _magicHeader) {
      throw const FormatException('Invalid backup file format');
    }

    // Extract salt and ciphertext
    final saltStart = headerBytes.length;
    final saltEnd = saltStart + 16;
    final salt = bytes.sublist(saltStart, saltEnd);
    final ciphertextWithTag = bytes.sublist(saltEnd);

    // Derive symmetric key
    final symKey = CryptoUtils.hkdf(
      ikm: utf8.encode(passphrase.trim()),
      salt: salt,
      info: utf8.encode('BHAROSA_ENCRYPTED_BACKUP_KEY'),
      length: 32,
    );

    // Decrypt payload
    Uint8List cleartext;
    try {
      cleartext = await CryptoEngine.decryptAead(
        payload: ciphertextWithTag,
        symmetricKey: symKey,
      );
    } catch (e) {
      throw const FormatException('Incorrect password or corrupted backup file');
    }

    final rawJson = utf8.decode(cleartext);
    final map = jsonDecode(rawJson) as Map<String, dynamic>;

    // Restore Identity Keys
    final privKeyStr = map['identityPrivateKey'] as String?;
    final pubKeyStr = map['identityPublicKey'] as String?;
    if (privKeyStr != null && pubKeyStr != null) {
      await _secureStorage.saveIdentityKeyPair(
        privateKey: base64Decode(privKeyStr),
        publicKey: base64Decode(pubKeyStr),
      );
    }

    // Restore recovery phrase if available
    final phrase = map['recoveryPhrase'] as String?;
    if (phrase != null && phrase.trim().isNotEmpty) {
      await _secureStorage.saveRecoveryPhrase(phrase.trim());
    }

    // Restore SQLite database tables
    final dbMap = map['database'] as Map<String, dynamic>?;
    if (dbMap != null) {
      await _databaseService.importAllData(dbMap);
    }

    // Restore active profile
    final activeId = map['activeProfileId'] as String?;
    if (activeId != null) {
      await _secureStorage.setActiveProfileId(activeId);
      final profile = await _databaseService.getProfile(activeId);
      if (profile != null) return profile;
    }

    // Fallback: fetch first profile or create a default one
    final profiles = await _databaseService.getAllProfiles();
    if (profiles.isNotEmpty) {
      await _secureStorage.setActiveProfileId(profiles.first.id);
      return profiles.first;
    }

    final fallback = Profile(
      id: 'restored_user',
      displayName: 'Bharosa User',
      isIncognito: false,
      isHidden: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _databaseService.saveProfile(fallback);
    await _secureStorage.setActiveProfileId(fallback.id);
    return fallback;
  }
}
