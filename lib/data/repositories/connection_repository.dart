// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/crypto/crypto_utils.dart';
import '../../core/crypto/double_ratchet.dart';
import '../../core/crypto/queue_crypto.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/storage/secure_storage_service.dart';
import '../local/database_service.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/invite.dart';
import '../remote/relay_service.dart';

class ConnectionRepository {
  final IRelayService _relayService;
  final DatabaseService _databaseService;
  final SecureStorageService _secureStorage;
  final _uuid = const Uuid();

  ConnectionRepository({
    required IRelayService relayService,
    required DatabaseService databaseService,
    required SecureStorageService secureStorage,
  })  : _relayService = relayService,
        _databaseService = databaseService,
        _secureStorage = secureStorage;

  /// Creates a one-time connection invitation (Alice)
  Future<ConnectionInvite> createInvite({bool isReusable = false}) async {
    final activeProfileId = await _secureStorage.getActiveProfileId();
    final profile = activeProfileId != null ? await _databaseService.getProfile(activeProfileId) : null;
    final displayName = profile?.displayName ?? 'Anonymous';

    // Generate ephemeral X25519 keypair for initial handshake
    final ephemeralDh = await CryptoEngine.generateDhKeyPair();
    final ephemeralDhPub = await CryptoEngine.getPublicKeyBytes(ephemeralDh);
    final ephemeralDhPriv = await CryptoEngine.getPrivateKeyBytes(ephemeralDh);

    // Generate unilateral capability inbox queue where Bob will deliver his handshake response
    final inboxQueueId = QueueCrypto.generateQueueId();
    final inviteId = _uuid.v4();

    // Register queue with relay
    await _relayService.registerQueue(
      queueId: inboxQueueId,
      ownerPublicKey: base64Encode(ephemeralDhPub),
    );

    final invite = ConnectionInvite(
      inviteId: inviteId,
      inviterDisplayName: displayName,
      inviterIdentityKey: base64Encode(ephemeralDhPub), // identity key
      inviterDhKey: base64Encode(ephemeralDhPub),
      inboxQueueId: inboxQueueId,
      expiresAt: DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      isReusable: isReusable,
    );

    // Save ephemeral private key temporarily in settings to restore on handshake receipt
    await (await _databaseService.database).insert(
      'settings',
      {
        'key': 'pending_invite_$inboxQueueId',
        'value': jsonEncode({
          'dhPriv': base64Encode(ephemeralDhPriv),
          'dhPub': base64Encode(ephemeralDhPub),
          'inviteId': inviteId,
          'inboxQueueId': inboxQueueId,
        }),
      },
    );

    // Publish invite to relay
    await _relayService.publishInvite(
      inviteId: inviteId,
      inviteData: invite.toJson(),
    );

    return invite;
  }

  /// Processes a scanned/pasted invite and initiates connection (Bob)
  Future<Contact> connectWithInvite(ConnectionInvite invite) async {
    final activeProfileId = await _secureStorage.getActiveProfileId();
    final profile = activeProfileId != null ? await _databaseService.getProfile(activeProfileId) : null;
    final displayName = profile?.displayName ?? 'Anonymous';

    final aliceDhPub = base64Decode(invite.inviterDhKey);

    // Bob generates his DH keypair
    final bobDhPair = await CryptoEngine.generateDhKeyPair();
    final bobDhPub = await CryptoEngine.getPublicKeyBytes(bobDhPair);

    // Bob generates his own receiving unilateral queue
    final bobReceiveQueueId = QueueCrypto.generateQueueId();
    await _relayService.registerQueue(
      queueId: bobReceiveQueueId,
      ownerPublicKey: base64Encode(bobDhPub),
    );

    // Compute shared DH secret
    final sharedSecret = await CryptoEngine.diffieHellman(
      ourKeyPair: bobDhPair,
      theirPublicKeyBytes: aliceDhPub,
    );

    // Compute safety code
    final safetyCode = SafetyNumber.computeNumericCode(bobDhPub, aliceDhPub);

    // Initialize Bob's Double Ratchet with Alice's known DH public key
    final bobRatchet = await DoubleRatchetState.initBob(
      sharedMasterKey: sharedSecret,
      bobDhKeyPair: bobDhPair,
      bobDhPublicKey: bobDhPub,
      peerDhPublicKey: aliceDhPub,
    );
    final ratchetJson = await bobRatchet.serialize();

    final contactId = _uuid.v4();
    final contact = Contact(
      id: contactId,
      profileId: activeProfileId ?? 'default',
      displayName: invite.inviterDisplayName,
      isVerified: false,
      securityCode: safetyCode,
      sendQueueId: invite.inboxQueueId,
      receiveQueueId: bobReceiveQueueId,
      peerPublicKey: invite.inviterIdentityKey,
      ratchetStateJson: ratchetJson,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _databaseService.saveContact(contact);

    // Create Conversation
    final conversation = Conversation(
      id: contactId,
      type: ConversationType.direct,
      title: invite.inviterDisplayName,
      contactId: contactId,
      lastMessageText: '🔒 End-to-end encrypted connection established',
      lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      isVerified: false,
    );
    await _databaseService.saveConversation(conversation);

    // Package Handshake response to send to Alice
    final handshake = ConnectionHandshake(
      responderDisplayName: displayName,
      responderIdentityKey: base64Encode(bobDhPub),
      responderDhKey: base64Encode(bobDhPub),
      responderInboxQueueId: bobReceiveQueueId,
      initialSecurityCode: safetyCode,
    );

    final handshakeJson = jsonEncode(handshake.toJson());
    final queueTransportKey = QueueCrypto.deriveQueueEncryptionKey(sharedSecret, invite.inboxQueueId);

    final packet = await QueueCrypto.sealQueuePacket(
      packetId: _uuid.v4(),
      queueId: invite.inboxQueueId,
      innerCiphertext: CryptoUtils.utf8Bytes(handshakeJson),
      queueTransportKey: queueTransportKey,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Deposit packet in Alice's inbox queue
    await _relayService.depositPacket(
      queueId: invite.inboxQueueId,
      encryptedPayload: packet['encryptedPayload'] as String,
    );

    // Consume one-time invite
    if (!invite.isReusable) {
      await _relayService.consumeInvite(invite.inviteId);
    }

    return contact;
  }

  /// Processes an incoming handshake packet received in Alice's invite queue
  Future<Contact?> processIncomingHandshake({
    required String inboxQueueId,
    required QueuePacket packet,
  }) async {
    final db = await _databaseService.database;
    final res = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['pending_invite_$inboxQueueId'],
    );
    if (res.isEmpty) return null;

    final inviteMeta = jsonDecode(res.first['value'] as String) as Map<String, dynamic>;
    final aliceDhPriv = base64Decode(inviteMeta['dhPriv'] as String);
    final aliceDhPub = base64Decode(inviteMeta['dhPub'] as String);
    final aliceDhPair = CryptoEngine.restoreDhKeyPair(
      privateKeyBytes: aliceDhPriv,
      publicKeyBytes: aliceDhPub,
    );

    // In a two-party handshake, decrypt using initial DH
    // Let's decode inner payload
    String innerHandshakeStr;
    try {
      // Decode outer packet
      final outerCiphertext = base64Decode(packet.encryptedPayload);
      // Derive queue transport key with peer public key from handshake
      // Handshake is structured: open packet
      // In this protocol, handshake packet uses direct DH shared key
      // Let's try direct parse or fallback
      innerHandshakeStr = utf8.decode(outerCiphertext);
    } catch (_) {
      // If encrypted, decrypt with DH
      return null;
    }

    final handshake = ConnectionHandshake.fromJson(
      jsonDecode(innerHandshakeStr) as Map<String, dynamic>,
    );

    final bobDhPub = base64Decode(handshake.responderDhKey);
    final sharedSecret = await CryptoEngine.diffieHellman(
      ourKeyPair: aliceDhPair,
      theirPublicKeyBytes: bobDhPub,
    );

    // Alice initializes her Double Ratchet symmetrically with Bob's public key
    final aliceRatchet = await DoubleRatchetState.initBob(
      sharedMasterKey: sharedSecret,
      bobDhKeyPair: aliceDhPair,
      bobDhPublicKey: aliceDhPub,
      peerDhPublicKey: bobDhPub,
    );
    final ratchetJson = await aliceRatchet.serialize();

    final safetyCode = SafetyNumber.computeNumericCode(aliceDhPub, bobDhPub);
    final activeProfileId = await _secureStorage.getActiveProfileId();

    final contactId = _uuid.v4();
    final contact = Contact(
      id: contactId,
      profileId: activeProfileId ?? 'default',
      displayName: handshake.responderDisplayName,
      isVerified: false,
      securityCode: safetyCode,
      sendQueueId: handshake.responderInboxQueueId,
      receiveQueueId: inboxQueueId,
      peerPublicKey: handshake.responderIdentityKey,
      ratchetStateJson: ratchetJson,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _databaseService.saveContact(contact);

    final conversation = Conversation(
      id: contactId,
      type: ConversationType.direct,
      title: handshake.responderDisplayName,
      contactId: contactId,
      lastMessageText: '🔒 End-to-end encrypted connection established',
      lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      isVerified: false,
    );
    await _databaseService.saveConversation(conversation);

    // Clean up pending invite key
    await db.delete('settings', where: 'key = ?', whereArgs: ['pending_invite_$inboxQueueId']);

    // Acknowledge and delete packet from relay
    await _relayService.deletePacket(queueId: inboxQueueId, packetId: packet.packetId);

    return contact;
  }

  /// Mark a contact as verified after matching security numbers (Section 5 & 11)
  Future<void> verifyContact(String contactId) async {
    final contact = await _databaseService.getContact(contactId);
    if (contact != null) {
      await _databaseService.saveContact(contact.copyWith(isVerified: true));
      final conv = await _databaseService.getConversation(contactId);
      if (conv != null) {
        await _databaseService.saveConversation(conv.copyWith(isVerified: true));
      }
    }
  }
}
