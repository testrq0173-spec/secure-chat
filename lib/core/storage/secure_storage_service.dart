import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/crypto_utils.dart';

/// Secure hardware-backed storage for cryptographic key material and DB passphrases
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const _kIdentityPrivateKey = 'bharosa_identity_priv_key';
  static const _kIdentityPublicKey = 'bharosa_identity_pub_key';
  static const _kDbPassphrase = 'bharosa_db_passphrase';
  static const _kPinHash = 'bharosa_pin_hash';
  static const _kPinSalt = 'bharosa_pin_salt';
  static const _kBiometricEnabled = 'bharosa_biometric_enabled';
  static const _kLockTimeoutSeconds = 'bharosa_lock_timeout_seconds';
  static const _kActiveProfileId = 'bharosa_active_profile_id';
  static const _kScreenshotBlock = 'bharosa_screenshot_block';
  static const _kIncognitoMode = 'bharosa_incognito_mode';
  static const _kRecoveryPhrase = 'bharosa_recovery_phrase';

  /// Generates or retrieves the device master database passphrase
  Future<String> getOrCreateDbPassphrase() async {
    var passphrase = await _storage.read(key: _kDbPassphrase);
    if (passphrase == null) {
      final random = CryptoUtils.randomBytes(32);
      passphrase = CryptoUtils.toHex(random);
      await _storage.write(key: _kDbPassphrase, value: passphrase);
    }
    return passphrase;
  }

  /// Stores Master Identity KeyPair (Ed25519)
  Future<void> saveIdentityKeyPair({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) async {
    await _storage.write(key: _kIdentityPrivateKey, value: base64Encode(privateKey));
    await _storage.write(key: _kIdentityPublicKey, value: base64Encode(publicKey));
  }

  Future<Uint8List?> getIdentityPrivateKey() async {
    final str = await _storage.read(key: _kIdentityPrivateKey);
    return str != null ? base64Decode(str) : null;
  }

  Future<Uint8List?> getIdentityPublicKey() async {
    final str = await _storage.read(key: _kIdentityPublicKey);
    return str != null ? base64Decode(str) : null;
  }

  /// Stores 12-word mnemonic recovery phrase securely
  Future<void> saveRecoveryPhrase(String phrase) async {
    await _storage.write(key: _kRecoveryPhrase, value: phrase.trim());
  }

  Future<String?> getRecoveryPhrase() async {
    return await _storage.read(key: _kRecoveryPhrase);
  }

  /// PIN Authentication Management
  Future<void> setAppPin(String pin) async {
    final salt = CryptoUtils.randomBytes(16);
    final saltHex = CryptoUtils.toHex(salt);
    final hash = CryptoUtils.sha256(CryptoUtils.utf8Bytes(pin + saltHex));
    final hashHex = CryptoUtils.toHex(hash);

    await _storage.write(key: _kPinSalt, value: saltHex);
    await _storage.write(key: _kPinHash, value: hashHex);
  }

  Future<bool> verifyAppPin(String pin) async {
    final saltHex = await _storage.read(key: _kPinSalt);
    final hashHex = await _storage.read(key: _kPinHash);
    if (saltHex == null || hashHex == null) return false;

    final computedHash = CryptoUtils.sha256(CryptoUtils.utf8Bytes(pin + saltHex));
    final computedHex = CryptoUtils.toHex(computedHash);

    return CryptoUtils.constantTimeEquals(
      CryptoUtils.utf8Bytes(computedHex),
      CryptoUtils.utf8Bytes(hashHex),
    );
  }

  Future<bool> isPinSet() async {
    final hash = await _storage.read(key: _kPinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> removePin() async {
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
  }

  /// App Lock & Privacy Settings
  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(key: _kBiometricEnabled, value: enabled ? '1' : '0');
  }

  Future<bool> isBiometricsEnabled() async {
    final val = await _storage.read(key: _kBiometricEnabled);
    return val == '1';
  }

  Future<void> setLockTimeout(int seconds) async {
    await _storage.write(key: _kLockTimeoutSeconds, value: seconds.toString());
  }

  Future<int> getLockTimeout() async {
    final val = await _storage.read(key: _kLockTimeoutSeconds);
    return val != null ? int.tryParse(val) ?? 60 : 60; // default 60s
  }

  Future<void> setScreenshotBlock(bool block) async {
    await _storage.write(key: _kScreenshotBlock, value: block ? '1' : '0');
  }

  Future<bool> isScreenshotBlocked() async {
    final val = await _storage.read(key: _kScreenshotBlock);
    return val == '1';
  }

  Future<void> setIncognito(bool enabled) async {
    await _storage.write(key: _kIncognitoMode, value: enabled ? '1' : '0');
  }

  Future<bool> isIncognito() async {
    final val = await _storage.read(key: _kIncognitoMode);
    return val == '1';
  }

  Future<void> setActiveProfileId(String id) async {
    await _storage.write(key: _kActiveProfileId, value: id);
  }

  Future<String?> getActiveProfileId() async {
    return await _storage.read(key: _kActiveProfileId);
  }

  /// Emergency wipe of all local cryptographic keys
  Future<void> wipeAllKeys() async {
    await _storage.deleteAll();
  }
}
