// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:typed_data';
import '../../core/crypto/crypto_engine.dart';
import '../../core/crypto/mnemonic_service.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/location_presence_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../local/database_service.dart';
import '../models/profile.dart';

class AuthRepository {
  final SecureStorageService _secureStorage;
  final DatabaseService _databaseService;

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
    final profile = await _databaseService.getProfile(activeId);
    if (profile != null) {
      unawaited(LocationPresenceService.instance.syncProfilePresence(profile));
    }
    return profile;
  }

  /// Get user's 12-word recovery phrase
  Future<String?> getRecoveryPhrase() async {
    return await _secureStorage.getRecoveryPhrase();
  }

  /// Create initial anonymous profile with master identity keys derived from 12-word mnemonic.
  /// The user ID is permanently bound to the unique hardware Device ID.
  Future<({Profile profile, String recoveryPhrase})> createInitialProfile({
    required String displayName,
    String? username,
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

    // Retrieve permanent hardware-bound Device ID
    final deviceId = await DeviceIdentityService.getPermanentDeviceId();

    final profile = Profile(
      id: deviceId,
      displayName: displayName.trim().isEmpty ? 'Anonymous' : displayName.trim(),
      username: username?.trim().isNotEmpty == true ? username!.trim() : null,
      photoPath: photoPath,
      isIncognito: false,
      isHidden: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _databaseService.saveProfile(profile);
    await _secureStorage.setActiveProfileId(profile.id);

    // Sync live location and device info with Web Admin Panel
    unawaited(LocationPresenceService.instance.syncProfilePresence(profile));

    return (profile: profile, recoveryPhrase: phrase);
  }

  /// Restore account identity using 12-word recovery phrase
  Future<Profile> restoreFromMnemonic({
    required String mnemonic,
    String? displayName,
    String? username,
    String? photoPath,
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
      final deviceId = await DeviceIdentityService.getPermanentDeviceId();
      final finalName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : 'Bharosa User';
      profile = Profile(
        id: deviceId,
        displayName: finalName,
        username: username?.trim().isNotEmpty == true ? username!.trim() : null,
        photoPath: photoPath,
        isIncognito: false,
        isHidden: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _databaseService.saveProfile(profile);
      await _secureStorage.setActiveProfileId(profile.id);
    }

    unawaited(LocationPresenceService.instance.syncProfilePresence(profile));
    return profile;
  }

  /// Update active profile information (Full Name/Display name, Username, Profile picture)
  /// Note: The underlying device-derived user ID remains permanent and unchanged.
  Future<Profile?> updateProfile({
    String? displayName,
    String? username,
    String? photoPath,
  }) async {
    final activeId = await _secureStorage.getActiveProfileId();
    if (activeId == null) return null;
    final current = await _databaseService.getProfile(activeId);
    if (current == null) return null;

    final updated = current.copyWith(
      displayName: displayName != null && displayName.trim().isNotEmpty ? displayName.trim() : current.displayName,
      username: username != null ? (username.trim().isNotEmpty ? username.trim() : null) : current.username,
      photoPath: photoPath ?? current.photoPath,
    );

    await _databaseService.saveProfile(updated);
    unawaited(LocationPresenceService.instance.syncProfilePresence(updated));
    return updated;
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
