import 'dart:convert';
import 'dart:typed_data';
import 'crypto_engine.dart';
import 'crypto_utils.dart';

/// Capability Queue addressing, cryptographic envelopes, and queue-level encryption
class QueueCrypto {
  QueueCrypto._();

  /// Generates a high-entropy 128-bit unguessable capability Queue ID
  static String generateQueueId() {
    return 'q_${CryptoUtils.randomToken(16)}';
  }

  /// Derives a queue-level transport symmetric key from shared secret to ensure
  /// the packet payload is encrypted twice before transit.
  static Uint8List deriveQueueEncryptionKey(Uint8List sharedSecret, String queueId) {
    return CryptoUtils.hkdf(
      ikm: sharedSecret,
      salt: CryptoUtils.utf8Bytes(queueId),
      info: CryptoUtils.utf8Bytes('Bharosa-QueueTransportKey'),
      length: 32,
    );
  }

  /// Seals a double-ratchet encrypted packet into a queue transport packet with queue-level encryption
  static Future<Map<String, dynamic>> sealQueuePacket({
    required String packetId,
    required String queueId,
    required Uint8List innerCiphertext,
    required Uint8List queueTransportKey,
    required int timestamp,
  }) async {
    // Encrypt inner ciphertext with queue-level key
    final outerCiphertext = await CryptoEngine.encryptAead(
      plaintext: innerCiphertext,
      symmetricKey: queueTransportKey,
      associatedData: CryptoUtils.utf8Bytes('$queueId:$packetId:$timestamp'),
    );

    return {
      'packetId': packetId,
      'queueId': queueId,
      'encryptedPayload': base64Encode(outerCiphertext),
      'timestamp': timestamp,
      'size': outerCiphertext.length,
    };
  }

  /// Opens and decrypts a queue transport packet back to the double-ratchet inner packet
  static Future<Uint8List> openQueuePacket({
    required Map<String, dynamic> packetJson,
    required Uint8List queueTransportKey,
  }) async {
    final packetId = packetJson['packetId'] as String;
    final queueId = packetJson['queueId'] as String;
    final timestamp = packetJson['timestamp'] as int;
    final outerCiphertext = base64Decode(packetJson['encryptedPayload'] as String);

    return await CryptoEngine.decryptAead(
      payload: outerCiphertext,
      symmetricKey: queueTransportKey,
      associatedData: CryptoUtils.utf8Bytes('$queueId:$packetId:$timestamp'),
    );
  }
}
