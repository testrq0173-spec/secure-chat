import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bharosa/core/crypto/crypto_engine.dart';
import 'package:bharosa/core/crypto/crypto_utils.dart';
import 'package:bharosa/core/crypto/double_ratchet.dart';
import 'package:bharosa/core/crypto/queue_crypto.dart';
import 'package:bharosa/core/crypto/safety_number.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CryptoUtils & Padding Tests', () {
    test('Pads and unpads plaintext to nearest bucket', () {
      final plaintext = CryptoUtils.utf8Bytes('Hello, zero-knowledge postbox!');
      final padded = CryptoUtils.padToBucket(plaintext);

      // Padded length must be one of the bucket sizes (e.g. 128)
      expect(CryptoUtils.paddingBuckets.contains(padded.length), isTrue);
      expect(padded.length, greaterThanOrEqualTo(plaintext.length + 4));

      final unpadded = CryptoUtils.unpadFromBucket(padded);
      expect(CryptoUtils.utf8String(unpadded), equals('Hello, zero-knowledge postbox!'));
    });

    test('Generates 128-bit random token capability for queue IDs', () {
      final token = CryptoUtils.randomToken(16);
      expect(token.isNotEmpty, isTrue);
      expect(token.contains('='), isFalse);

      final queueId = QueueCrypto.generateQueueId();
      expect(queueId.startsWith('q_'), isTrue);
    });

    test('Constant-time equality prevents timing leak', () {
      final a = [1, 2, 3, 4];
      final b = [1, 2, 3, 4];
      final c = [1, 2, 3, 5];
      expect(CryptoUtils.constantTimeEquals(a, b), isTrue);
      expect(CryptoUtils.constantTimeEquals(a, c), isFalse);
    });
  });

  group('Safety Number Tests', () {
    test('Computes identical 6-digit safety code regardless of key order', () {
      final keyA = CryptoUtils.randomBytes(32);
      final keyB = CryptoUtils.randomBytes(32);

      final code1 = SafetyNumber.computeNumericCode(keyA, keyB);
      final code2 = SafetyNumber.computeNumericCode(keyB, keyA);

      expect(code1, equals(code2));
      expect(code1.length, equals(7)); // "XXX XXX" format
    });
  });

  group('Double Ratchet End-to-End Tests', () {
    test('Alice and Bob exchange encrypted messages with forward secrecy', () async {
      // 1. Initial shared master key from Diffie-Hellman handshake
      final sharedMasterKey = CryptoUtils.randomBytes(32);

      // Bob generates his DH keypair
      final bobDhPair = await CryptoEngine.generateDhKeyPair();
      final bobDhPub = await CryptoEngine.getPublicKeyBytes(bobDhPair);

      // Alice initializes ratchet with Bob's public key
      final aliceRatchet = await DoubleRatchetState.initAlice(
        sharedMasterKey: sharedMasterKey,
        bobDhPublicKey: bobDhPub,
      );

      // Bob initializes ratchet
      final bobRatchet = await DoubleRatchetState.initBob(
        sharedMasterKey: sharedMasterKey,
        bobDhKeyPair: bobDhPair,
        bobDhPublicKey: bobDhPub,
      );

      // 2. Alice sends message to Bob
      const msg1 = 'Secret message from Alice to Bob';
      final packet1 = await aliceRatchet.encrypt(CryptoUtils.utf8Bytes(msg1));

      // Bob decrypts message 1
      final decrypted1Bytes = await bobRatchet.decrypt(packet1);
      final decrypted1 = CryptoUtils.utf8String(decrypted1Bytes);
      expect(decrypted1, equals(msg1));

      // 3. Bob responds to Alice (ratchet steps forward)
      const msg2 = 'Received loud and clear, Alice!';
      final packet2 = await bobRatchet.encrypt(CryptoUtils.utf8Bytes(msg2));

      // Alice decrypts response
      final decrypted2Bytes = await aliceRatchet.decrypt(packet2);
      final decrypted2 = CryptoUtils.utf8String(decrypted2Bytes);
      expect(decrypted2, equals(msg2));

      // 4. Test state serialization and restore
      final aliceStateJson = await aliceRatchet.serialize();
      final restoredAlice = DoubleRatchetState.deserialize(aliceStateJson);

      const msg3 = 'Message after state restore';
      final packet3 = await restoredAlice.encrypt(CryptoUtils.utf8Bytes(msg3));
      final decrypted3Bytes = await bobRatchet.decrypt(packet3);
      expect(CryptoUtils.utf8String(decrypted3Bytes), equals(msg3));
    });

    test('Bob can send first to Alice when initialized with Alice DH key', () async {
      final sharedMasterKey = CryptoUtils.randomBytes(32);
      final aliceDhPair = await CryptoEngine.generateDhKeyPair();
      final aliceDhPub = await CryptoEngine.getPublicKeyBytes(aliceDhPair);
      final bobDhPair = await CryptoEngine.generateDhKeyPair();
      final bobDhPub = await CryptoEngine.getPublicKeyBytes(bobDhPair);

      final bobRatchet = await DoubleRatchetState.initBob(
        sharedMasterKey: sharedMasterKey,
        bobDhKeyPair: bobDhPair,
        bobDhPublicKey: bobDhPub,
        peerDhPublicKey: aliceDhPub,
      );

      final aliceRatchet = await DoubleRatchetState.initBob(
        sharedMasterKey: sharedMasterKey,
        bobDhKeyPair: aliceDhPair,
        bobDhPublicKey: aliceDhPub,
        peerDhPublicKey: bobDhPub,
      );

      // Bob sends first!
      const bobMsg = 'Hey Alice, I connected!';
      final bobPacket = await bobRatchet.encrypt(CryptoUtils.utf8Bytes(bobMsg));
      final aliceDecryptedBytes = await aliceRatchet.decrypt(bobPacket);
      expect(CryptoUtils.utf8String(aliceDecryptedBytes), equals(bobMsg));

      // Alice replies to Bob!
      const aliceReply = 'Welcome Bob, nice to connect!';
      final alicePacket = await aliceRatchet.encrypt(CryptoUtils.utf8Bytes(aliceReply));
      final bobDecryptedBytes = await bobRatchet.decrypt(alicePacket);
      expect(CryptoUtils.utf8String(bobDecryptedBytes), equals(aliceReply));
    });
  });

  group('Queue Transport Double Encryption Tests', () {
    test('Seals and opens queue packet using queue-level key', () async {
      final sharedSecret = CryptoUtils.randomBytes(32);
      final queueId = QueueCrypto.generateQueueId();
      final transportKey = QueueCrypto.deriveQueueEncryptionKey(sharedSecret, queueId);

      final innerPayload = CryptoUtils.utf8Bytes('{"action":"message","data":"top_secret"}');
      final sealed = await QueueCrypto.sealQueuePacket(
        packetId: 'pkt-123',
        queueId: queueId,
        innerCiphertext: innerPayload,
        queueTransportKey: transportKey,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(sealed['encryptedPayload'], isNotEmpty);

      final opened = await QueueCrypto.openQueuePacket(
        packetJson: sealed,
        queueTransportKey: transportKey,
      );

      expect(utf8.decode(opened), equals('{"action":"message","data":"top_secret"}'));
    });
  });
}
