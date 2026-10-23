import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_utils.dart';

/// Cryptographic primitives wrapper using audited algorithms (X25519, Ed25519, ChaCha20-Poly1305)
class CryptoEngine {
  CryptoEngine._();

  static final X25519 _x25519 = X25519();
  static final Ed25519 _ed25519 = Ed25519();
  static final Cipher _aead = Chacha20.poly1305Aead();

  /// Generates an X25519 keypair for Diffie-Hellman ratchet
  static Future<SimpleKeyPair> generateDhKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Extracts raw 32-byte public key from SimpleKeyPair
  static Future<Uint8List> getPublicKeyBytes(SimpleKeyPair keyPair) async {
    final pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  /// Extracts raw 32-byte private key from SimpleKeyPair
  static Future<Uint8List> getPrivateKeyBytes(SimpleKeyPair keyPair) async {
    final priv = await keyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(priv);
  }

  /// Restores SimpleKeyPair from raw 32-byte private and public key bytes
  static SimpleKeyPair restoreDhKeyPair({
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
  }) {
    return SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Computes Diffie-Hellman shared secret using X25519
  static Future<Uint8List> diffieHellman({
    required SimpleKeyPair ourKeyPair,
    required List<int> theirPublicKeyBytes,
  }) async {
    final theirPublicKey = SimplePublicKey(
      theirPublicKeyBytes,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ourKeyPair,
      remotePublicKey: theirPublicKey,
    );
    final secretBytes = await sharedSecret.extractBytes();
    return Uint8List.fromList(secretBytes);
  }

  /// Generates an Ed25519 keypair for digital signatures (queue ownership proofs)
  static Future<SimpleKeyPair> generateSigningKeyPair() async {
    return await _ed25519.newKeyPair();
  }

  /// Restores Ed25519 SimpleKeyPair from raw private/public bytes
  static SimpleKeyPair restoreSigningKeyPair({
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
  }) {
    return SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  }

  /// Signs data with Ed25519 private key
  static Future<Uint8List> sign({
    required List<int> data,
    required SimpleKeyPair signingKeyPair,
  }) async {
    final signature = await _ed25519.sign(data, keyPair: signingKeyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies an Ed25519 digital signature
  static Future<bool> verifySignature({
    required List<int> data,
    required List<int> signatureBytes,
    required List<int> publicKeyBytes,
  }) async {
    try {
      final pubKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final sig = Signature(signatureBytes, publicKey: pubKey);
      return await _ed25519.verify(data, signature: sig);
    } catch (_) {
      return false;
    }
  }

  /// Encrypts plaintext with ChaCha20-Poly1305 AEAD with optional Associated Data (AAD)
  /// Returns: Nonce (12 bytes) + Ciphertext + Poly1305 MAC (16 bytes)
  static Future<Uint8List> encryptAead({
    required List<int> plaintext,
    required List<int> symmetricKey,
    List<int>? associatedData,
  }) async {
    final secretKey = SecretKey(symmetricKey);
    final nonce = CryptoUtils.randomBytes(12);

    final secretBox = await _aead.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: associatedData ?? <int>[],
    );

    // Concatenate nonce (12B) + ciphertext + mac (16B)
    final macBytes = secretBox.mac.bytes;
    final int cipherLength = secretBox.cipherText.length;
    final int totalLength = 12 + cipherLength + macBytes.length;
    final result = Uint8List(totalLength);
    result.setRange(0, 12, nonce);
    result.setRange(12, 12 + cipherLength, secretBox.cipherText);
    result.setRange(12 + cipherLength, totalLength, macBytes);

    return result;
  }

  /// Decrypts ChaCha20-Poly1305 AEAD payload (Nonce 12B + Ciphertext + MAC 16B)
  static Future<Uint8List> decryptAead({
    required List<int> payload,
    required List<int> symmetricKey,
    List<int>? associatedData,
  }) async {
    if (payload.length < 28) { // 12B nonce + 16B MAC
      throw const FormatException('Payload too short for AEAD');
    }

    final nonce = payload.sublist(0, 12);
    final mac = payload.sublist(payload.length - 16);
    final cipherText = payload.sublist(12, payload.length - 16);

    final secretKey = SecretKey(symmetricKey);
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(mac),
    );

    final clearText = await _aead.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: associatedData ?? <int>[],
    );

    return Uint8List.fromList(clearText);
  }
}
