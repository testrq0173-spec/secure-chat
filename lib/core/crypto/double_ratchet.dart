import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_engine.dart';
import 'crypto_utils.dart';

/// Ratchet Message Header transmitted alongside the ciphertext
class RatchetHeader {
  final Uint8List dhPublicKey;
  final int messageNumber;
  final int previousChainLength;

  RatchetHeader({
    required this.dhPublicKey,
    required this.messageNumber,
    required this.previousChainLength,
  });

  /// Serializes header to binary bytes for AAD and packet wrapping
  Uint8List toBytes() {
    final bytes = Uint8List(32 + 4 + 4);
    bytes.setRange(0, 32, dhPublicKey);
    final bd = ByteData.sublistView(bytes);
    bd.setUint32(32, messageNumber, Endian.big);
    bd.setUint32(36, previousChainLength, Endian.big);
    return bytes;
  }

  factory RatchetHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < 40) {
      throw const FormatException('Invalid ratchet header length');
    }
    final dhPk = Uint8List.sublistView(bytes, 0, 32);
    final bd = ByteData.sublistView(bytes);
    final msgNum = bd.getUint32(32, Endian.big);
    final prevLen = bd.getUint32(36, Endian.big);
    return RatchetHeader(
      dhPublicKey: dhPk,
      messageNumber: msgNum,
      previousChainLength: prevLen,
    );
  }

  Map<String, dynamic> toJson() => {
    'dhPublicKey': base64Encode(dhPublicKey),
    'messageNumber': messageNumber,
    'previousChainLength': previousChainLength,
  };

  factory RatchetHeader.fromJson(Map<String, dynamic> json) => RatchetHeader(
    dhPublicKey: base64Decode(json['dhPublicKey'] as String),
    messageNumber: json['messageNumber'] as int,
    previousChainLength: json['previousChainLength'] as int,
  );
}

/// Encrypted message package containing the ratchet header and ciphertext
class EncryptedMessagePacket {
  final RatchetHeader header;
  final Uint8List ciphertext;

  EncryptedMessagePacket({required this.header, required this.ciphertext});

  Map<String, dynamic> toJson() => {
    'header': header.toJson(),
    'ciphertext': base64Encode(ciphertext),
  };

  factory EncryptedMessagePacket.fromJson(Map<String, dynamic> json) =>
      EncryptedMessagePacket(
        header: RatchetHeader.fromJson(json['header'] as Map<String, dynamic>),
        ciphertext: base64Decode(json['ciphertext'] as String),
      );

  Uint8List toCombinedBytes() {
    final headerBytes = header.toBytes();
    final combined = Uint8List(headerBytes.length + ciphertext.length);
    combined.setRange(0, headerBytes.length, headerBytes);
    combined.setRange(headerBytes.length, combined.length, ciphertext);
    return combined;
  }

  factory EncryptedMessagePacket.fromCombinedBytes(Uint8List bytes) {
    final header = RatchetHeader.fromBytes(Uint8List.sublistView(bytes, 0, 40));
    final ciphertext = Uint8List.sublistView(bytes, 40);
    return EncryptedMessagePacket(header: header, ciphertext: ciphertext);
  }
}

/// Full Double Ratchet State machine with Forward Secrecy and Break-in Recovery
class DoubleRatchetState {
  SimpleKeyPair dhSendingKeyPair;
  Uint8List dhSendingPublicKey;
  Uint8List? dhReceivingPublicKey;
  Uint8List rootKey;
  Uint8List? sendingChainKey;
  Uint8List? receivingChainKey;
  int sendingMessageNumber;
  int receivingMessageNumber;
  int previousChainLength;
  final Map<String, Uint8List> skippedMessageKeys; // Key: "dhPubBase64:msgNum" -> msgKey

  DoubleRatchetState({
    required this.dhSendingKeyPair,
    required this.dhSendingPublicKey,
    required this.dhReceivingPublicKey,
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    this.sendingMessageNumber = 0,
    this.receivingMessageNumber = 0,
    this.previousChainLength = 0,
    Map<String, Uint8List>? skippedMessageKeys,
  }) : skippedMessageKeys = skippedMessageKeys ?? <String, Uint8List>{};

  /// Initializes Alice's ratchet (initiator)
  static Future<DoubleRatchetState> initAlice({
    required Uint8List sharedMasterKey,
    required Uint8List bobDhPublicKey,
    SimpleKeyPair? aliceDhKeyPair,
  }) async {
    final pair = aliceDhKeyPair ?? await CryptoEngine.generateDhKeyPair();
    final pubKey = await CryptoEngine.getPublicKeyBytes(pair);

    // Initial DH step
    final dhShared = await CryptoEngine.diffieHellman(
      ourKeyPair: pair,
      theirPublicKeyBytes: bobDhPublicKey,
    );

    // Derive root key and sending chain key
    final derived = CryptoUtils.hkdf(
      ikm: dhShared,
      salt: sharedMasterKey,
      info: CryptoUtils.utf8Bytes('DoubleRatchet-RootStep'),
      length: 64,
    );
    final newRootKey = derived.sublist(0, 32);
    final sendingChainKey = derived.sublist(32, 64);

    return DoubleRatchetState(
      dhSendingKeyPair: pair,
      dhSendingPublicKey: pubKey,
      dhReceivingPublicKey: bobDhPublicKey,
      rootKey: newRootKey,
      sendingChainKey: sendingChainKey,
      receivingChainKey: null,
      sendingMessageNumber: 0,
      receivingMessageNumber: 0,
    );
  }

  /// Initializes Bob's ratchet (responder)
  static Future<DoubleRatchetState> initBob({
    required Uint8List sharedMasterKey,
    required SimpleKeyPair bobDhKeyPair,
    required Uint8List bobDhPublicKey,
    Uint8List? peerDhPublicKey,
  }) async {
    return DoubleRatchetState(
      dhSendingKeyPair: bobDhKeyPair,
      dhSendingPublicKey: bobDhPublicKey,
      dhReceivingPublicKey: peerDhPublicKey,
      rootKey: sharedMasterKey,
      sendingChainKey: null,
      receivingChainKey: null,
      sendingMessageNumber: 0,
      receivingMessageNumber: 0,
    );
  }

  /// Encrypts an outgoing message
  Future<EncryptedMessagePacket> encrypt(Uint8List plaintext) async {
    if (sendingChainKey == null) {
      if (dhReceivingPublicKey != null) {
        // Step DH to generate Bob's sending chain and new DH public key
        dhSendingKeyPair = await CryptoEngine.generateDhKeyPair();
        dhSendingPublicKey = await CryptoEngine.getPublicKeyBytes(dhSendingKeyPair);

        final dhShared = await CryptoEngine.diffieHellman(
          ourKeyPair: dhSendingKeyPair,
          theirPublicKeyBytes: dhReceivingPublicKey!,
        );
        final derived = CryptoUtils.hkdf(
          ikm: dhShared,
          salt: rootKey,
          info: CryptoUtils.utf8Bytes('DoubleRatchet-RootStep'),
          length: 64,
        );
        rootKey = derived.sublist(0, 32);
        sendingChainKey = derived.sublist(32, 64);
      } else {
        throw StateError('Sending chain is not initialized');
      }
    }

    // Symmetric chain step
    final keys = _stepChainKey(sendingChainKey!);
    sendingChainKey = keys.nextChainKey;
    final messageKey = keys.messageKey;

    final header = RatchetHeader(
      dhPublicKey: dhSendingPublicKey,
      messageNumber: sendingMessageNumber,
      previousChainLength: previousChainLength,
    );
    sendingMessageNumber++;

    // Pad plaintext to bucket
    final paddedPlaintext = CryptoUtils.padToBucket(plaintext);

    // Encrypt with ChaCha20-Poly1305 with header as AAD
    final ciphertext = await CryptoEngine.encryptAead(
      plaintext: paddedPlaintext,
      symmetricKey: messageKey,
      associatedData: header.toBytes(),
    );

    return EncryptedMessagePacket(header: header, ciphertext: ciphertext);
  }

  /// Decrypts an incoming message
  Future<Uint8List> decrypt(EncryptedMessagePacket packet) async {
    final header = packet.header;

    // Check if key was previously skipped (out-of-order delivery)
    final skippedKeyId = '${base64Encode(header.dhPublicKey)}:${header.messageNumber}';
    if (skippedMessageKeys.containsKey(skippedKeyId)) {
      final messageKey = skippedMessageKeys.remove(skippedKeyId)!;
      final padded = await CryptoEngine.decryptAead(
        payload: packet.ciphertext,
        symmetricKey: messageKey,
        associatedData: header.toBytes(),
      );
      return CryptoUtils.unpadFromBucket(padded);
    }

    // If new DH key received, perform DH ratchet step
    if (dhReceivingPublicKey == null ||
        !CryptoUtils.constantTimeEquals(header.dhPublicKey, dhReceivingPublicKey!)) {
      await _skipMessageKeys(header.previousChainLength);
      await _dhRatchetStep(header.dhPublicKey);
    }

    // Skip any message keys up to current message number
    await _skipMessageKeys(header.messageNumber);

    // Advance receiving chain
    final keys = _stepChainKey(receivingChainKey!);
    receivingChainKey = keys.nextChainKey;
    receivingMessageNumber++;

    final padded = await CryptoEngine.decryptAead(
      payload: packet.ciphertext,
      symmetricKey: keys.messageKey,
      associatedData: header.toBytes(),
    );

    return CryptoUtils.unpadFromBucket(padded);
  }

  Future<void> _skipMessageKeys(int until) async {
    if (receivingChainKey == null) return;
    if (receivingMessageNumber + 2000 < until) {
      throw StateError('Too many messages to skip (possible DoS)');
    }
    while (receivingMessageNumber < until) {
      final keys = _stepChainKey(receivingChainKey!);
      receivingChainKey = keys.nextChainKey;
      final keyId = '${base64Encode(dhReceivingPublicKey!)}:$receivingMessageNumber';
      skippedMessageKeys[keyId] = keys.messageKey;
      receivingMessageNumber++;
    }
  }

  Future<void> _dhRatchetStep(Uint8List theirNewDhPublicKey) async {
    previousChainLength = sendingMessageNumber;
    sendingMessageNumber = 0;
    receivingMessageNumber = 0;
    dhReceivingPublicKey = theirNewDhPublicKey;

    // 1. DH step with their new key and our current key
    final dhShared1 = await CryptoEngine.diffieHellman(
      ourKeyPair: dhSendingKeyPair,
      theirPublicKeyBytes: dhReceivingPublicKey!,
    );
    final derived1 = CryptoUtils.hkdf(
      ikm: dhShared1,
      salt: rootKey,
      info: CryptoUtils.utf8Bytes('DoubleRatchet-RootStep'),
      length: 64,
    );
    rootKey = derived1.sublist(0, 32);
    receivingChainKey = derived1.sublist(32, 64);

    // 2. Generate our new DH keypair and perform step 2
    dhSendingKeyPair = await CryptoEngine.generateDhKeyPair();
    dhSendingPublicKey = await CryptoEngine.getPublicKeyBytes(dhSendingKeyPair);

    final dhShared2 = await CryptoEngine.diffieHellman(
      ourKeyPair: dhSendingKeyPair,
      theirPublicKeyBytes: dhReceivingPublicKey!,
    );
    final derived2 = CryptoUtils.hkdf(
      ikm: dhShared2,
      salt: rootKey,
      info: CryptoUtils.utf8Bytes('DoubleRatchet-RootStep'),
      length: 64,
    );
    rootKey = derived2.sublist(0, 32);
    sendingChainKey = derived2.sublist(32, 64);
  }

  static ({Uint8List nextChainKey, Uint8List messageKey}) _stepChainKey(Uint8List chainKey) {
    final nextChainKey = CryptoUtils.hmacSha256(chainKey, const [0x01]);
    final messageKey = CryptoUtils.hmacSha256(chainKey, const [0x02]);
    return (nextChainKey: nextChainKey, messageKey: messageKey);
  }

  /// Serialize ratchet state to JSON string for encrypted local storage
  Future<String> serialize() async {
    final privKeyBytes = await CryptoEngine.getPrivateKeyBytes(dhSendingKeyPair);
    final map = {
      'dhSendingPrivateKey': base64Encode(privKeyBytes),
      'dhSendingPublicKey': base64Encode(dhSendingPublicKey),
      'dhReceivingPublicKey': dhReceivingPublicKey != null ? base64Encode(dhReceivingPublicKey!) : null,
      'rootKey': base64Encode(rootKey),
      'sendingChainKey': sendingChainKey != null ? base64Encode(sendingChainKey!) : null,
      'receivingChainKey': receivingChainKey != null ? base64Encode(receivingChainKey!) : null,
      'sendingMessageNumber': sendingMessageNumber,
      'receivingMessageNumber': receivingMessageNumber,
      'previousChainLength': previousChainLength,
      'skippedMessageKeys': skippedMessageKeys.map((k, v) => MapEntry(k, base64Encode(v))),
    };
    return jsonEncode(map);
  }

  /// Restore ratchet state from JSON string
  static DoubleRatchetState deserialize(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final privBytes = base64Decode(map['dhSendingPrivateKey'] as String);
    final pubBytes = base64Decode(map['dhSendingPublicKey'] as String);
    final keyPair = CryptoEngine.restoreDhKeyPair(
      privateKeyBytes: privBytes,
      publicKeyBytes: pubBytes,
    );

    final skipped = <String, Uint8List>{};
    if (map['skippedMessageKeys'] != null) {
      final sMap = map['skippedMessageKeys'] as Map<String, dynamic>;
      for (final e in sMap.entries) {
        skipped[e.key] = base64Decode(e.value as String);
      }
    }

    return DoubleRatchetState(
      dhSendingKeyPair: keyPair,
      dhSendingPublicKey: pubBytes,
      dhReceivingPublicKey: map['dhReceivingPublicKey'] != null
          ? base64Decode(map['dhReceivingPublicKey'] as String)
          : null,
      rootKey: base64Decode(map['rootKey'] as String),
      sendingChainKey: map['sendingChainKey'] != null
          ? base64Decode(map['sendingChainKey'] as String)
          : null,
      receivingChainKey: map['receivingChainKey'] != null
          ? base64Decode(map['receivingChainKey'] as String)
          : null,
      sendingMessageNumber: map['sendingMessageNumber'] as int,
      receivingMessageNumber: map['receivingMessageNumber'] as int,
      previousChainLength: map['previousChainLength'] as int,
      skippedMessageKeys: skipped,
    );
  }
}
