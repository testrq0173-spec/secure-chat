// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/storage/secure_storage_service.dart';
import '../local/database_service.dart';
import '../models/profile.dart';

class AuthRepository {
  final SecureStorageService _secureStorage;
  final DatabaseService _databaseService;
  final _uuid = const Uuid();

  AuthRepository({
    required SecureStorageService secureStorage,
    required DatabaseService databaseService,
  })  : _secureStorage = secureStorage,
        _databaseService = databaseService;

  /// Check if user has already onboarded and created a profile
  Future<bool> hasProfile() async {
    final activeId = await _secureStorage.getActiveProfileId();
    if (activeId == null) return false;
    final profile = await _databaseService.getProfile(activeId);
    return profile != null;
  }

  /// Get currently active profile
  Future<Profile?> getCurrentProfile() async {
    final activeId = await _secureStorage.getActiveProfileId();
    if (activeId == null) return null;
    return await _databaseService.getProfile(activeId);
  }

  /// Create initial anonymous profile with master identity keys
  Future<Profile> createInitialProfile({
    required String displayName,
    String? photoPath,
  }) async {
    // Generate Ed25519 identity keypair
    final keyPair = await CryptoEngine.generateSigningKeyPair();
    final pubKey = await CryptoEngine.getPublicKeyBytes(keyPair);
    final privKey = await CryptoEngine.getPrivateKeyBytes(keyPair);

    await _secureStorage.saveIdentityKeyPair(
      privateKey: privKey,
      publicKey: pubKey,
    );

    final profile = Profile(
      id: _uuid.v4(),
      displayName: displayName.trim().isEmpty ? 'Anonymous' : displayName.trim(),
      photoPath: photoPath,
      isIncognito: false,
      isHidden: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _databaseService.saveProfile(profile);
    await _secureStorage.setActiveProfileId(profile.id);

    return profile;
  }

  /// Get public identity key bytes
  Future<Uint8List> getIdentityPublicKey() async {
    final pub = await _secureStorage.getIdentityPublicKey();
    if (pub == null) {
      final pair = await CryptoEngine.generateSigningKeyPair();
      final p = await CryptoEngine.getPublicKeyBytes(pair);
      final priv = await CryptoEngine.getPrivateKeyBytes(pair);
      await _secureStorage.saveIdentityKeyPair(privateKey: priv, publicKey: p);
      return p;
    }
    return pub;
  }
}
