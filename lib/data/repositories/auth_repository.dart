// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/crypto/mnemonic_service.dart';
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

  /// Get user's 12-word recovery phrase
  Future<String?> getRecoveryPhrase() async {
    return await _secureStorage.getRecoveryPhrase();
  }

  /// Create initial anonymous profile with master identity keys derived from 12-word mnemonic
  Future<({Profile profile, String recoveryPhrase})> createInitialProfile({
    required String displayName,
    String? photoPath,
    String? existingPhrase,
  }) async {
    final phrase = existingPhrase ?? MnemonicService.generateMnemonic();
    
    // Deterministically derive master Ed25519 identity keypair
    final keyPair = await MnemonicService.deriveSigningKeyPair(phrase);
    final pubKey = await CryptoEngine.getPublicKeyBytes(keyPair);
    final privKey = await CryptoEngine.getPrivateKeyBytes(keyPair);

    await _secureStorage.saveIdentityKeyPair(
      privateKey: privKey,
      publicKey: pubKey,
    );
    await _secureStorage.saveRecoveryPhrase(phrase);

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

    return (profile: profile, recoveryPhrase: phrase);
  }

  /// Restore account identity using 12-word recovery phrase
  Future<Profile> restoreFromMnemonic({
    required String mnemonic,
    String? displayName,
  }) async {
    final cleanPhrase = mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (!MnemonicService.validateMnemonic(cleanPhrase)) {
      throw const FormatException('Invalid 12-word recovery phrase checksum');
    }

    final keyPair = await MnemonicService.deriveSigningKeyPair(cleanPhrase);
    final pubKey = await CryptoEngine.getPublicKeyBytes(keyPair);
    final privKey = await CryptoEngine.getPrivateKeyBytes(keyPair);

    await _secureStorage.saveIdentityKeyPair(
      privateKey: privKey,
      publicKey: pubKey,
    );
    await _secureStorage.saveRecoveryPhrase(cleanPhrase);

    // Check if an existing profile exists in the local DB
    final activeId = await _secureStorage.getActiveProfileId();
    Profile? profile;
    if (activeId != null) {
      profile = await _databaseService.getProfile(activeId);
    }

    if (profile == null) {
      final finalName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : 'Bharosa User';
      profile = Profile(
        id: _uuid.v4(),
        displayName: finalName,
        isIncognito: false,
        isHidden: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _databaseService.saveProfile(profile);
      await _secureStorage.setActiveProfileId(profile.id);
    }

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
