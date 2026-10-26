// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/crypto/crypto_utils.dart';
import '../../core/crypto/double_ratchet.dart';
import '../../core/storage/secure_storage_service.dart';
import '../local/database_service.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../remote/relay_service.dart';
import 'connection_repository.dart';

class ChatRepository {
  final IRelayService _relayService;
  final DatabaseService _databaseService;
  final SecureStorageService _secureStorage;
  final ConnectionRepository? _connectionRepository;
  final _uuid = const Uuid();

  final Map<String, StreamSubscription> _queueSubscriptions = {};
  final StreamController<Message> _incomingMessageStream = StreamController<Message>.broadcast();
  final StreamController<Contact> _connectionRequestStream = StreamController<Contact>.broadcast();
  final Map<String, List<String?>> _chunkBuffers = {};
  final Map<String, String> _completedMediaFiles = {};
  Timer? _heartbeatTimer;

  ChatRepository({
    required IRelayService relayService,
    required DatabaseService databaseService,
    required SecureStorageService secureStorage,
    ConnectionRepository? connectionRepository,
  })  : _relayService = relayService,
        _databaseService = databaseService,
        _secureStorage = secureStorage,
        _connectionRepository = connectionRepository;

  Stream<Message> get onIncomingMessage => _incomingMessageStream.stream;
  Stream<Contact> get onConnectionRequest => _connectionRequestStream.stream;

  /// Initializes listeners for all active contact receiving queues & pending invite queues
  Future<void> startListeningToQueues() async {
    final contacts = await _databaseService.getAllContacts();
    for (final contact in contacts) {
      _listenToContactQueue(contact);
    }

    // Restore listeners for all active invite queues
    final db = await _databaseService.database;
    final inviteSettings = await db.query(
      'settings',
      where: "key LIKE 'pending_invite_%'",
    );
    final queueIdsToSync = <String>[
      ...contacts.map((c) => c.receiveQueueId),
    ];
    for (final row in inviteSettings) {
      try {
        final meta = jsonDecode(row['value'] as String) as Map<String, dynamic>;
        final inboxQueueId = meta['inboxQueueId'] as String;
        queueIdsToSync.add(inboxQueueId);
        await listenToInviteQueue(inboxQueueId);
      } catch (_) {}
    }

    // Sync FCM tokens to Firestore for WhatsApp-style push delivery
    try {
      await PushNotificationService.instance.syncTokensForQueues(queueIdsToSync);
    } catch (_) {}

    // Start 3-second heartbeat sync for guaranteed zero-delay delivery
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final activeContacts = await _databaseService.getAllContacts();
      for (final c in activeContacts) {
        await _drainContactQueue(c);
      }
      final db = await _databaseService.database;
      final inviteRows = await db.query(
        'settings',
        where: "key LIKE 'pending_invite_%'",
      );
      for (final row in inviteRows) {
        try {
          final meta = jsonDecode(row['value'] as String) as Map<String, dynamic>;
          final inboxQueueId = meta['inboxQueueId'] as String;
          await _drainInviteQueue(inboxQueueId);
        } catch (_) {}
      }
    });
  }

  void _listenToContactQueue(Contact contact) {
    if (_queueSubscriptions.containsKey(contact.receiveQueueId)) return;

    final sub = _relayService.listenToQueue(contact.receiveQueueId).listen((packet) async {
      await _processIncomingPacket(contact, packet);
    });
    _queueSubscriptions[contact.receiveQueueId] = sub;

    // Immediately drain pending packets for instant message receipt
    _drainContactQueue(contact);
  }

  Future<void> _drainContactQueue(Contact contact) async {
    try {
      final packets = await _relayService.fetchPackets(contact.receiveQueueId);
      for (final packet in packets) {
        await _processIncomingPacket(contact, packet);
      }
    } catch (_) {}
  }

  /// Listens to a pending invite inbox queue for incoming handshakes
  Future<void> listenToInviteQueue(String inboxQueueId) async {
    if (_queueSubscriptions.containsKey(inboxQueueId)) return;

    final sub = _relayService.listenToQueue(inboxQueueId).listen((packet) async {
      await _processIncomingInvitePacket(inboxQueueId, packet);
    });
    _queueSubscriptions[inboxQueueId] = sub;

    // Immediately drain pending packets
    _drainInviteQueue(inboxQueueId);
  }

  Future<void> _drainInviteQueue(String inboxQueueId) async {
    try {
      final packets = await _relayService.fetchPackets(inboxQueueId);
      for (final packet in packets) {
        await _processIncomingInvitePacket(inboxQueueId, packet);
      }
    } catch (_) {}
  }

  Future<void> _processIncomingInvitePacket(String inboxQueueId, QueuePacket packet) async {
    try {
      // 1. Try decoding as Handshake envelope
      try {
        final outerBytes = base64Decode(packet.encryptedPayload);
        final outerJsonStr = utf8.decode(outerBytes);
        final outerEnvelope = jsonDecode(outerJsonStr) as Map<String, dynamic>;
        if (outerEnvelope['action'] == 'handshake') {
          final contact = await _connectionRepository?.processIncomingHandshake(
            inboxQueueId: inboxQueueId,
            packet: packet,
          );
          if (contact != null) {
            _listenToContactQueue(contact);
            _connectionRequestStream.add(contact);
            _incomingMessageStream.add(Message(
              id: _uuid.v4(),
              conversationId: contact.id,
              senderId: contact.id,
              senderName: contact.displayName,
              type: MessageType.text,
              content: 'New connection request',
              status: MessageStatus.delivered,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ));
          }
          return;
        }
      } catch (_) {}

      // 2. If contact already exists for this receive queue, process as message
      final contact = await _databaseService.getContactByReceiveQueue(inboxQueueId);
      if (contact != null) {
        await _processIncomingPacket(contact, packet);
      }
    } catch (e) {
      debugPrint('Error processing incoming invite queue packet: $e');
    }
  }

  /// Ensures a specific contact or conversation queue is actively listened to
  Future<void> ensureListening(String conversationId) async {
    final contact = await _databaseService.getContact(conversationId);
    if (contact != null) {
      _listenToContactQueue(contact);
    }
  }

  void listenToContact(Contact contact) {
    _listenToContactQueue(contact);
  }


  /// Process an incoming encrypted packet from a peer's queue
  Future<void> _processIncomingPacket(Contact contact, QueuePacket queuePacket) async {
    try {
      if (contact.ratchetStateJson == null) return;

      // 1. Restore Double Ratchet State
      final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);

      // 2. Unpack outer queue payload
      final outerCiphertext = base64Decode(queuePacket.encryptedPayload);

      // 3. Deserialize Ratchet packet
      final ratchetPacket = EncryptedMessagePacket.fromCombinedBytes(outerCiphertext);

      // 4. Decrypt and unpad
      final plaintextBytes = await ratchet.decrypt(ratchetPacket);
      final plaintextJson = utf8.decode(plaintextBytes);
      final payload = jsonDecode(plaintextJson) as Map<String, dynamic>;

      // 5. Save updated ratchet state
      final updatedRatchetJson = await ratchet.serialize();
      await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchetJson));

      // 6. Handle action / control payloads
      final action = payload['action'] as String? ?? 'message';

      if (action == 'delete_everyone') {
        final targetMessageId = payload['targetMessageId'] as String;
        await _databaseService.deleteMessageForMe(targetMessageId);
        // Acknowledge and delete packet
        await _relayService.deletePacket(queueId: contact.receiveQueueId, packetId: queuePacket.packetId);
        return;
      }

      if (action == 'reaction') {
        final targetMessageId = payload['targetMessageId'] as String;
        final emoji = payload['emoji'] as String;
        final reaction = Reaction(
          id: _uuid.v4(),
          messageId: targetMessageId,
          contactId: contact.id,
          emoji: emoji,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        await _databaseService.saveReaction(reaction);
        await _relayService.deletePacket(queueId: contact.receiveQueueId, packetId: queuePacket.packetId);
        return;
      }

      if (action == 'request_approved') {
        await _databaseService.approveContact(contact.id);
        final conv = await _databaseService.getConversation(contact.id);
        if (conv != null) {
          await _databaseService.saveConversation(conv.copyWith(
            requestStatus: 'approved',
            lastMessageText: 'Request approved! You can now chat.',
            lastMessageTime: DateTime.now().millisecondsSinceEpoch,
          ));
        }
        await _relayService.deletePacket(queueId: contact.receiveQueueId, packetId: queuePacket.packetId);
        await NotificationService.instance.showMessageNotification(
          title: contact.displayName,
          body: 'Accepted your connection request',
          conversationId: contact.id,
        );
        _incomingMessageStream.add(Message(
          id: _uuid.v4(),
          conversationId: contact.id,
          senderId: contact.id,
          senderName: contact.displayName,
          type: MessageType.text,
          content: '🔒 Connection request accepted! You can now chat.',
          status: MessageStatus.delivered,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
        return;
      }

      if (action == 'request_denied') {
        await _databaseService.blockContact(contact.id);
        await _relayService.deletePacket(queueId: contact.receiveQueueId, packetId: queuePacket.packetId);
        return;
      }

      if (action == 'file_chunk') {
        final targetMessageId = payload['targetMessageId'] as String;
        final chunkIndex = payload['chunkIndex'] as int;
        final totalChunks = payload['totalChunks'] as int;
        final chunkData = payload['chunkData'] as String;
        final fName = payload['fileName'] as String? ?? 'media_$targetMessageId.dat';

        _chunkBuffers.putIfAbsent(targetMessageId, () => List<String?>.filled(totalChunks, null));
        _chunkBuffers[targetMessageId]![chunkIndex] = chunkData;

        if (!_chunkBuffers[targetMessageId]!.contains(null)) {
          final fullBase64 = _chunkBuffers[targetMessageId]!.join();
          _chunkBuffers.remove(targetMessageId);

          try {
            final fileBytes = base64Decode(fullBase64);
            final appDir = await getApplicationDocumentsDirectory();
            final mediaDir = Directory('${appDir.path}/media');
            if (!await mediaDir.exists()) {
              await mediaDir.create(recursive: true);
            }
            final ext = p.extension(fName).isNotEmpty ? p.extension(fName) : '.dat';
            final targetFile = File('${mediaDir.path}/$targetMessageId$ext');
            await targetFile.writeAsBytes(fileBytes);

            final existingMsg = await _databaseService.getMessage(targetMessageId);
            if (existingMsg != null) {
              final updatedMsg = existingMsg.copyWith(filePath: targetFile.path);
              await _databaseService.saveMessage(updatedMsg);
              _incomingMessageStream.add(updatedMsg);
            } else {
              _completedMediaFiles[targetMessageId] = targetFile.path;
            }
          } catch (e) {
            debugPrint('Error reassembling file chunks: $e');
          }
        }

        await _relayService.deletePacket(queueId: contact.receiveQueueId, packetId: queuePacket.packetId);
        return;
      }

      // Normal message
      final msgId = payload['id'] as String? ?? _uuid.v4();
      final content = payload['content'] as String? ?? '';
      final typeStr = payload['type'] as String? ?? 'text';
      final type = MessageType.values.firstWhere((e) => e.name == typeStr, orElse: () => MessageType.text);

      int? expiresAt;
      if (contact.disappearingDurationSeconds > 0) {
        expiresAt = DateTime.now().millisecondsSinceEpoch + (contact.disappearingDurationSeconds * 1000);
      }

      // Extract media file data if transferred inline or resolve from completed chunks
      String? localSavedPath = payload['filePath'] as String?;
      final fileData = payload['fileData'] as String?;
      if (fileData != null) {
        try {
          final fileBytes = base64Decode(fileData);
          final appDir = await getApplicationDocumentsDirectory();
          final mediaDir = Directory('${appDir.path}/media');
          if (!await mediaDir.exists()) {
            await mediaDir.create(recursive: true);
          }
          final originalName = payload['fileName'] as String? ?? 'media_$msgId.dat';
          final ext = p.extension(originalName).isNotEmpty ? p.extension(originalName) : '.dat';
          final targetFile = File('${mediaDir.path}/$msgId$ext');
          await targetFile.writeAsBytes(fileBytes);
          localSavedPath = targetFile.path;
        } catch (e) {
          debugPrint('Error saving incoming media file: $e');
        }
      } else if (_completedMediaFiles.containsKey(msgId)) {
        localSavedPath = _completedMediaFiles.remove(msgId);
      } else {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final mediaDir = Directory('${appDir.path}/media');
          if (await mediaDir.exists()) {
            final files = mediaDir.listSync().whereType<File>().where((f) => p.basenameWithoutExtension(f.path) == msgId);
            if (files.isNotEmpty) {
              localSavedPath = files.first.path;
            }
          }
        } catch (_) {}
      }

      final message = Message(
        id: msgId,
        conversationId: contact.id,
        senderId: contact.id,
        senderName: contact.displayName,
        type: type,
        content: content,
        filePath: localSavedPath,
        fileName: payload['fileName'] as String?,
        fileSize: payload['fileSize'] as int?,
        mediaDurationMs: payload['mediaDurationMs'] as int?,
        status: MessageStatus.delivered,
        timestamp: payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        expiresAt: expiresAt,
        replyToId: payload['replyToId'] as String?,
        replyToText: payload['replyToText'] as String?,
        replyToSender: payload['replyToSender'] as String?,
      );

      await _databaseService.saveMessage(message);

      // Update Conversation snippet and unread count
      final conv = await _databaseService.getConversation(contact.id);
      if (conv != null) {
        await _databaseService.saveConversation(
          conv.copyWith(
            lastMessageText: content.isNotEmpty ? content : '[${type.name}]',
            lastMessageTime: message.timestamp,
            unreadCount: conv.unreadCount + 1,
          ),
        );
      }

      _incomingMessageStream.add(message);

      // Trigger Push Notification
      try {
        String notificationBody = content;
        if (notificationBody.isEmpty) {
          switch (type) {
            case MessageType.voice:
              notificationBody = '🎤 Voice message';
              break;
            case MessageType.image:
              notificationBody = '📷 Photo';
              break;
            case MessageType.video:
              notificationBody = '🎥 Video';
              break;
            case MessageType.file:
              notificationBody = '📄 ${payload['fileName'] ?? 'Document'}';
              break;
            default:
              notificationBody = '🔒 New encrypted message';
          }
        }

        await NotificationService.instance.showMessageNotification(
          title: contact.displayName,
          body: notificationBody,
          conversationId: contact.id,
        );
      } catch (e) {
        debugPrint('Notification trigger warning: $e');
      }

      // 7. Instant packet deletion from Blinded Postbox!
      await _relayService.deletePacket(
        queueId: contact.receiveQueueId,
        packetId: queuePacket.packetId,
      );
    } catch (e) {
      debugPrint('Error processing incoming queue packet: $e');
    }
  }

  /// Sends a 1-to-1 end-to-end encrypted message
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    MessageType type = MessageType.text,
    String? filePath,
    String? fileName,
    int? fileSize,
    int? mediaDurationMs,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
  }) async {
    final activeProfileId = await _secureStorage.getActiveProfileId();
    final profile = activeProfileId != null ? await _databaseService.getProfile(activeProfileId) : null;
    final senderName = profile?.displayName ?? 'Me';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final messageId = _uuid.v4();

    // Check if this is the "Notes to Self" conversation
    if (conversationId == 'notes_to_self') {
      final noteMessage = Message(
        id: messageId,
        conversationId: 'notes_to_self',
        senderId: 'self',
        senderName: 'Notes to Self',
        type: type,
        content: content,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        mediaDurationMs: mediaDurationMs,
        status: MessageStatus.delivered,
        timestamp: timestamp,
        isSavedNote: true,
      );
      await _databaseService.saveMessage(noteMessage);
      final noteConv = await _databaseService.getConversation('notes_to_self');
      if (noteConv != null) {
        await _databaseService.saveConversation(
          noteConv.copyWith(
            lastMessageText: content.isNotEmpty ? content : '[${type.name}]',
            lastMessageTime: timestamp,
          ),
        );
      }
      return noteMessage;
    }

    // Prepare inline media payload or chunks if file exists
    String? fileBase64;
    List<String>? fileChunks;
    if (filePath != null && File(filePath).existsSync()) {
      try {
        final bytes = await File(filePath).readAsBytes();
        if (bytes.length <= 250 * 1024) {
          fileBase64 = base64Encode(bytes);
        } else {
          const chunkSize = 200 * 1024;
          fileChunks = [];
          for (var i = 0; i < bytes.length; i += chunkSize) {
            final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
            fileChunks.add(base64Encode(bytes.sublist(i, end)));
          }
        }
      } catch (e) {
        debugPrint('File read error for inline encryption: $e');
      }
    }

    // Check if this is a group conversation
    final group = await _databaseService.getGroup(conversationId);
    if (group != null) {
      final message = Message(
        id: messageId,
        conversationId: conversationId,
        senderId: 'self',
        senderName: senderName,
        type: type,
        content: content,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        mediaDurationMs: mediaDurationMs,
        status: MessageStatus.delivered,
        timestamp: timestamp,
        replyToId: replyToId,
        replyToText: replyToText,
        replyToSender: replyToSender,
      );

      await _databaseService.saveMessage(message);

      final conv = await _databaseService.getConversation(conversationId);
      if (conv != null) {
        await _databaseService.saveConversation(
          conv.copyWith(
            lastMessageText: content.isNotEmpty ? content : '[${type.name}]',
            lastMessageTime: timestamp,
            draftText: '',
          ),
        );
      }

      // Fan-out to group members
      final members = await _databaseService.getGroupMembers(conversationId);
      for (final member in members) {
        if (member.contactId == 'self' || member.contactId == activeProfileId) continue;
        final memberContact = await _databaseService.getContact(member.contactId);
        if (memberContact != null && memberContact.ratchetStateJson != null) {
          try {
            final ratchet = DoubleRatchetState.deserialize(memberContact.ratchetStateJson!);
            final payload = {
              'id': messageId,
              'action': 'message',
              'groupId': conversationId,
              'groupName': group.name,
              'type': type.name,
              'content': content,
              'filePath': filePath,
              'fileName': fileName,
              'fileSize': fileSize,
              'mediaDurationMs': mediaDurationMs,
              'fileData': fileBase64,
              'timestamp': timestamp,
              'replyToId': replyToId,
              'replyToText': replyToText,
              'replyToSender': replyToSender,
            };
            final plaintextBytes = CryptoUtils.utf8Bytes(jsonEncode(payload));
            final encryptedPacket = await ratchet.encrypt(plaintextBytes);
            final updatedRatchetJson = await ratchet.serialize();
            await _databaseService.saveContact(memberContact.copyWith(ratchetStateJson: updatedRatchetJson));
            await _relayService.depositPacket(
              queueId: memberContact.sendQueueId,
              encryptedPayload: base64Encode(encryptedPacket.toCombinedBytes()),
            );
          } catch (e) {
            debugPrint('Failed to dispatch group packet to ${member.displayName}: $e');
          }
        }
      }
      return message;
    }

    final contact = await _databaseService.getContact(conversationId);
    if (contact == null) {
      throw StateError('Cannot send message: Contact not found');
    }

    if (contact.isBlocked || contact.requestStatus == 'blocked') {
      throw StateError('Cannot send message: Contact is blocked.');
    }

    if (contact.requestStatus == 'pending_outgoing') {
      final sentCount = await _databaseService.getSentMessagesCount(conversationId);
      if (sentCount >= 1) {
        throw StateError('Waiting for recipient to approve request. You can send more messages once approved.');
      }
    }

    int? expiresAt;
    if (contact.disappearingDurationSeconds > 0) {
      expiresAt = timestamp + (contact.disappearingDurationSeconds * 1000);
    }

    final message = Message(
      id: messageId,
      conversationId: conversationId,
      senderId: 'self',
      senderName: senderName,
      type: type,
      content: content,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mediaDurationMs: mediaDurationMs,
      status: MessageStatus.sending,
      timestamp: timestamp,
      expiresAt: expiresAt,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );

    // Save locally immediately
    await _databaseService.saveMessage(message);

    // Update conversation snippet and clear draft
    final conv = await _databaseService.getConversation(conversationId);
    if (conv != null) {
      await _databaseService.saveConversation(
        conv.copyWith(
          lastMessageText: content.isNotEmpty ? content : '[${type.name}]',
          lastMessageTime: timestamp,
          draftText: '',
        ),
      );
    }

    // Encrypt and dispatch in background
    try {
      if (contact.ratchetStateJson != null) {
        final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);

        final payload = {
          'id': messageId,
          'action': 'message',
          'type': type.name,
          'content': content,
          'filePath': filePath,
          'fileName': fileName,
          'fileSize': fileSize,
          'mediaDurationMs': mediaDurationMs,
          'fileData': fileBase64,
          'timestamp': timestamp,
          'replyToId': replyToId,
          'replyToText': replyToText,
          'replyToSender': replyToSender,
        };


        final plaintextBytes = CryptoUtils.utf8Bytes(jsonEncode(payload));
        final encryptedRatchetPacket = await ratchet.encrypt(plaintextBytes);

        // Serialize ratchet packet to bytes
        final combinedBytes = encryptedRatchetPacket.toCombinedBytes();

        // Save updated ratchet state
        final updatedRatchetJson = await ratchet.serialize();
        await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchetJson));

        // Deposit into recipient's sendQueueId
        await _relayService.depositPacket(
          queueId: contact.sendQueueId,
          encryptedPayload: base64Encode(combinedBytes),
        );

        // If file was chunked, dispatch chunks sequentially
        if (fileChunks != null && fileChunks.isNotEmpty) {
          for (var i = 0; i < fileChunks.length; i++) {
            final latestContact = await _databaseService.getContact(conversationId);
            if (latestContact != null && latestContact.ratchetStateJson != null) {
              final latestRatchet = DoubleRatchetState.deserialize(latestContact.ratchetStateJson!);
              final chunkPayload = {
                'action': 'file_chunk',
                'targetMessageId': messageId,
                'chunkIndex': i,
                'totalChunks': fileChunks.length,
                'chunkData': fileChunks[i],
                'fileName': fileName,
              };
              final chunkBytes = CryptoUtils.utf8Bytes(jsonEncode(chunkPayload));
              final chunkPacket = await latestRatchet.encrypt(chunkBytes);
              final updatedJson = await latestRatchet.serialize();
              await _databaseService.saveContact(latestContact.copyWith(ratchetStateJson: updatedJson));
              await _relayService.depositPacket(
                queueId: latestContact.sendQueueId,
                encryptedPayload: base64Encode(chunkPacket.toCombinedBytes()),
              );
            }
          }
        }
      }

      // Mark message delivered
      await _databaseService.updateMessageStatus(messageId, MessageStatus.delivered);
      _incomingMessageStream.add(message.copyWith(status: MessageStatus.delivered));
    } catch (e) {
      debugPrint('Failed to dispatch packet: $e');
      await _databaseService.updateMessageStatus(messageId, MessageStatus.failed);
      _incomingMessageStream.add(message.copyWith(status: MessageStatus.failed));
    }

    return message;
  }

  /// Sends a reaction emoji on an existing message
  Future<void> sendReaction({
    required String messageId,
    required String conversationId,
    required String emoji,
  }) async {
    final reaction = Reaction(
      id: _uuid.v4(),
      messageId: messageId,
      contactId: 'self',
      emoji: emoji,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _databaseService.saveReaction(reaction);

    final contact = await _databaseService.getContact(conversationId);
    if (contact != null && contact.ratchetStateJson != null) {
      final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);
      final payload = {
        'action': 'reaction',
        'targetMessageId': messageId,
        'emoji': emoji,
      };
      final encryptedPacket = await ratchet.encrypt(CryptoUtils.utf8Bytes(jsonEncode(payload)));
      final updatedRatchet = await ratchet.serialize();
      await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchet));

      await _relayService.depositPacket(
        queueId: contact.sendQueueId,
        encryptedPayload: base64Encode(encryptedPacket.toCombinedBytes()),
      );
    }
  }

  /// Edits an existing message with edit history
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    final msg = await _databaseService.getMessage(messageId);
    if (msg == null) return;

    final history = List<String>.from(msg.editHistory ?? []);
    history.add(msg.content);

    final updated = msg.copyWith(
      content: newContent,
      isEdited: true,
      editHistory: history,
    );
    await _databaseService.saveMessage(updated);
  }

  /// Deletes a message for me
  Future<void> deleteForMe(String messageId) async {
    await _databaseService.deleteMessageForMe(messageId);
  }

  /// Deletes a message for everyone (broadcasts delete command)
  Future<void> deleteForEveryone({
    required String messageId,
    required String conversationId,
  }) async {
    await _databaseService.deleteMessageForMe(messageId);

    final contact = await _databaseService.getContact(conversationId);
    if (contact != null && contact.ratchetStateJson != null) {
      final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);
      final payload = {
        'action': 'delete_everyone',
        'targetMessageId': messageId,
      };
      final encryptedPacket = await ratchet.encrypt(CryptoUtils.utf8Bytes(jsonEncode(payload)));
      final updatedRatchet = await ratchet.serialize();
      await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchet));

      await _relayService.depositPacket(
        queueId: contact.sendQueueId,
        encryptedPayload: base64Encode(encryptedPacket.toCombinedBytes()),
      );
    }
  }

  /// Creates a Group chat with members
  Future<Group> createGroup({
    required String name,
    required List<String> memberContactIds,
    String? avatar,
  }) async {
    final groupId = _uuid.v4();
    final group = Group(
      id: groupId,
      name: name,
      avatar: avatar,
      myRole: GroupRole.owner,
      inviteLink: 'bharosa://group?id=$groupId',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _databaseService.saveGroup(group);

    // Add self as owner
    await _databaseService.addGroupMember(
      GroupMember(
        groupId: groupId,
        contactId: 'self',
        displayName: 'Me',
        role: GroupRole.owner,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // Add selected members
    for (final contactId in memberContactIds) {
      final contact = await _databaseService.getContact(contactId);
      if (contact != null) {
        await _databaseService.addGroupMember(
          GroupMember(
            groupId: groupId,
            contactId: contact.id,
            displayName: contact.displayName,
            role: GroupRole.member,
            joinedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    }

    // Create group conversation entry
    final conv = Conversation(
      id: groupId,
      type: ConversationType.group,
      title: name,
      groupId: groupId,
      lastMessageText: 'Group created with ${memberContactIds.length + 1} members',
      lastMessageTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _databaseService.saveConversation(conv);

    return group;
  }

  /// Create or retrieve "Saved Notes" self-conversation
  Future<Conversation> getOrCreateSavedNotes() async {
    var conv = await _databaseService.getConversation('notes_to_self');
    if (conv == null) {
      conv = Conversation(
        id: 'notes_to_self',
        type: ConversationType.notes,
        title: 'Saved Notes',
        lastMessageText: 'Personal private vault',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      );
      await _databaseService.saveConversation(conv);
    }
    return conv;
  }

  Future<void> approveConnection(String conversationId) async {
    await _databaseService.approveContact(conversationId);
    final contact = await _databaseService.getContact(conversationId);
    if (contact != null && contact.ratchetStateJson != null) {
      try {
        final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);
        final payload = {
          'id': _uuid.v4(),
          'action': 'request_approved',
          'type': 'text',
          'content': '🔒 Connection request accepted',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        final plaintextBytes = CryptoUtils.utf8Bytes(jsonEncode(payload));
        final encryptedPacket = await ratchet.encrypt(plaintextBytes);
        final updatedRatchetJson = await ratchet.serialize();
        await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchetJson));
        await _relayService.depositPacket(
          queueId: contact.sendQueueId,
          encryptedPayload: base64Encode(encryptedPacket.toCombinedBytes()),
        );
      } catch (e) {
        debugPrint('Failed to dispatch approval packet: $e');
      }
    }
    _incomingMessageStream.add(Message(
      id: _uuid.v4(),
      conversationId: conversationId,
      senderId: 'self',
      senderName: 'Me',
      type: MessageType.text,
      content: '🔒 Connection request accepted',
      status: MessageStatus.delivered,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> denyConnection(String conversationId) async {
    await _databaseService.blockContact(conversationId);
    final contact = await _databaseService.getContact(conversationId);
    if (contact != null && contact.ratchetStateJson != null) {
      try {
        final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);
        final payload = {
          'id': _uuid.v4(),
          'action': 'request_denied',
          'type': 'text',
          'content': 'Connection request declined',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        final plaintextBytes = CryptoUtils.utf8Bytes(jsonEncode(payload));
        final encryptedPacket = await ratchet.encrypt(plaintextBytes);
        final updatedRatchetJson = await ratchet.serialize();
        await _databaseService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchetJson));
        await _relayService.depositPacket(
          queueId: contact.sendQueueId,
          encryptedPayload: base64Encode(encryptedPacket.toCombinedBytes()),
        );
      } catch (e) {
        debugPrint('Failed to dispatch deny packet: $e');
      }
    }
  }

  Future<void> unblockConnection(String contactId) async {
    await _databaseService.unblockContact(contactId);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    for (final sub in _queueSubscriptions.values) {
      sub.cancel();
    }
    _queueSubscriptions.clear();
    _incomingMessageStream.close();
    _connectionRequestStream.close();
  }
}

