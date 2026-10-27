// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
  final bool isAutoBackup;

  const BackupFileInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAt,
    this.isDefaultDirectory = false,
    this.isAutoBackup = false,
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

  /// Returns candidate persistent directories for saving and detecting backups
  Future<List<Directory>> getPersistentBackupDirectories() async {
    final dirs = <Directory>[];

    if (!kIsWeb && Platform.isAndroid) {
      // 1. Android Public Downloads folder (survives app uninstall)
      dirs.add(Directory('/storage/emulated/0/Download/Bharosa_Backups'));
      dirs.add(Directory('/storage/emulated/0/Download'));

      // 2. Android Public Documents folder
      dirs.add(Directory('/storage/emulated/0/Documents/Bharosa_Backups'));
      dirs.add(Directory('/storage/emulated/0/Documents'));
    }

    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        dirs.add(Directory(p.join(dl.path, 'Bharosa_Backups')));
        dirs.add(dl);
      }
    } catch (_) {}

    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dirs.add(Directory(p.join(ext.path, 'Bharosa_Backups')));
        dirs.add(ext);
      }
    } catch (_) {}

    try {
      final doc = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(doc.path, 'Bharosa_Backups')));
      dirs.add(doc);
    } catch (_) {}

    return dirs;
  }

  /// Writes backup bytes to multiple persistent locations so uninstallation doesn't erase them
  Future<File> _writeBackupBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    File? primaryFile;
    final candidateDirs = await getPersistentBackupDirectories();

    for (final dir in candidateDirs) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final f = File(p.join(dir.path, fileName));
        await f.writeAsBytes(bytes, flush: true);
        primaryFile ??= f;
      } catch (_) {
        // Silently continue to next directory if restricted
      }
    }

    if (primaryFile != null) {
      return primaryFile;
    }

    // Fallback to app documents
    final doc = await getApplicationDocumentsDirectory();
    final fallback = File(p.join(doc.path, fileName));
    await fallback.writeAsBytes(bytes, flush: true);
    return fallback;
  }

  /// Exports an AES/ChaCha20-Poly1305 encrypted backup
  Future<File> exportEncryptedBackup({
    required String passphrase,
    String? customFileName,
    bool saveWithSystemDialog = false,
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

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = customFileName ?? 'bharosa_backup_$timestamp.enc';

    // 7. Save file to persistent storage
    final file = await _writeBackupBytes(bytes: totalBytes, fileName: fileName);

    // 8. Optionally prompt native system save dialog so user can explicitly pick Downloads/Drive
    if (saveWithSystemDialog) {
      try {
        await FilePicker.saveFile(
          dialogTitle: 'Save Bharosa Encrypted Backup',
          fileName: fileName,
          bytes: totalBytes,
        );
      } catch (_) {}
    }

    // Record last backup metadata
    await _secureStorage.setLastBackupInfo(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: totalBytes.length,
    );

    return file;
  }

  /// WhatsApp-Style Automatic Periodic Backup
  /// Uses the user's master 12-word recovery phrase as the encryption passphrase.
  /// When reinstalling, entering the 12 words seamlessly restores chats!
  Future<File> exportAutoBackup() async {
    final phrase = await _secureStorage.getRecoveryPhrase();
    if (phrase == null || phrase.trim().isEmpty) {
      throw StateError('Cannot auto-backup: Master 12-word recovery phrase not initialized');
    }

    return await exportEncryptedBackup(
      passphrase: phrase.trim(),
      customFileName: 'bharosa_auto_backup.enc',
      saveWithSystemDialog: false,
    );
  }

  /// Automatically executes backup if > 24 hours have passed since last backup
  Future<File?> runAutoBackupIfNeeded() async {
    final enabled = await _secureStorage.isAutoBackupEnabled();
    if (!enabled) return null;

    final lastTime = await _secureStorage.getLastBackupTime();
    final now = DateTime.now().millisecondsSinceEpoch;
    const oneDay = 24 * 60 * 60 * 1000;

    if (lastTime != null && (now - lastTime) < oneDay) {
      return null;
    }

    try {
      return await exportAutoBackup();
    } catch (_) {
      return null;
    }
  }

  /// Intelligent Discovery Algorithm:
  /// Auto-scans all persistent device folders (Downloads, Documents, External storage) for backups
  Future<List<BackupFileInfo>> scanForLocalBackups() async {
    final results = <BackupFileInfo>[];
    final scannedPaths = <String>{};

    final candidateDirs = await getPersistentBackupDirectories();

    for (final dir in candidateDirs) {
      try {
        if (!await dir.exists()) continue;
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;
          if (scannedPaths.contains(entity.path)) continue;

          final name = p.basename(entity.path);
          final isCandidateName = name.startsWith('bharosa_') ||
              name.endsWith('.enc') ||
              name.endsWith('.bharosa_backup') ||
              name.endsWith('.bharosa');

          if (!isCandidateName) continue;

          try {
            final len = await entity.length();
            if (len < 64) continue; // Minimum size for header + salt + nonce + mac

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
                  isAutoBackup: name.contains('auto_backup'),
                ),
              );
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Sort: auto-backups and most recent backups first
    results.sort((a, b) {
      if (a.isAutoBackup && !b.isAutoBackup) return -1;
      if (!a.isAutoBackup && b.isAutoBackup) return 1;
      return b.modifiedAt.compareTo(a.modifiedAt);
    });

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
