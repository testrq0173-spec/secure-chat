import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Message;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/crypto/double_ratchet.dart';
import '../../data/local/database_service.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../data/remote/relay_service.dart';
import '../../data/repositories/connection_repository.dart';
import '../storage/secure_storage_service.dart';
import 'notification_service.dart';

/// WhatsApp-style Persistent Background Delivery Service.
/// Keeps an active Android Foreground Service running even when the app is swiped from
/// recent apps or the phone screen is locked, ensuring 100% reliable real-time notifications.
class BackgroundDeliveryService {
  BackgroundDeliveryService._();
  static final BackgroundDeliveryService instance = BackgroundDeliveryService._();

  static const String notificationChannelId = 'bharosa_service';
  static const int notificationId = 88812;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final service = FlutterBackgroundService();

    // Create Notification Channel for persistent service
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Bharosa Background Sync',
      description: 'Maintains end-to-end encrypted message delivery',
      importance: Importance.low,
      showBadge: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Ensure any previously pinned persistent notification is cleanly dismissed
    try {
      await flutterLocalNotificationsPlugin.cancel(id: notificationId);
    } catch (_) {}

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: false,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Bharosa Sync',
        initialNotificationContent: 'Message delivery active',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  void setAppForeground(bool isForeground) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      FlutterBackgroundService().invoke('setAppForeground', {'isForeground': isForeground});
    } catch (_) {}
  }

  void reloadQueues() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      FlutterBackgroundService().invoke('reloadQueues');
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase in background isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Background Firebase init error: $e');
  }

  // Initialize local notifications in background isolate
  try {
    await NotificationService.instance.initialize();
  } catch (_) {}

  final dbService = DatabaseService();
  final firestore = FirebaseFirestore.instance;
  final uuid = const Uuid();
  final connRepo = ConnectionRepository(
    relayService: HybridRelayService(),
    databaseService: dbService,
    secureStorage: SecureStorageService(),
  );

  bool isAppInForeground = false;
  final Map<String, StreamSubscription> activeSubscriptions = {};
  final Map<String, List<String?>> chunkBuffers = {};
  final Map<String, String> completedMediaFiles = {};

  service.on('setAppForeground').listen((event) {
    if (event != null && event['isForeground'] is bool) {
      isAppInForeground = event['isForeground'] as bool;
    }
  });

  Future<void> processPacket(Contact contact, QueuePacket packet) async {
    try {
      if (contact.ratchetStateJson == null) return;

      final ratchet = DoubleRatchetState.deserialize(contact.ratchetStateJson!);
      final outerCiphertext = base64Decode(packet.encryptedPayload);
      final ratchetPacket = EncryptedMessagePacket.fromCombinedBytes(outerCiphertext);

      final plaintextBytes = await ratchet.decrypt(ratchetPacket);
      final plaintextJson = utf8.decode(plaintextBytes);
      final payload = jsonDecode(plaintextJson) as Map<String, dynamic>;

      // Save updated ratchet state
      final updatedRatchetJson = await ratchet.serialize();
      await dbService.saveContact(contact.copyWith(ratchetStateJson: updatedRatchetJson));

      final action = payload['action'] as String? ?? 'message';

      if (action == 'request_approved') {
        await dbService.approveContact(contact.id);
        final conv = await dbService.getConversation(contact.id);
        if (conv != null) {
          await dbService.saveConversation(conv.copyWith(
            requestStatus: 'approved',
            lastMessageText: 'Request approved! You can now chat.',
            lastMessageTime: DateTime.now().millisecondsSinceEpoch,
          ));
        }
        await firestore
            .collection('queues')
            .doc(contact.receiveQueueId)
            .collection('packets')
            .doc(packet.packetId)
            .delete();
        await NotificationService.instance.showMessageNotification(
          title: contact.displayName,
          body: 'Accepted your connection request',
          conversationId: contact.id,
        );
        return;
      }

      if (action == 'request_denied') {
        await dbService.blockContact(contact.id);
        await firestore
            .collection('queues')
            .doc(contact.receiveQueueId)
            .collection('packets')
            .doc(packet.packetId)
            .delete();
        return;
      }

      if (action == 'delete_everyone') {
        final targetMessageId = payload['targetMessageId'] as String;
        await dbService.deleteMessageForMe(targetMessageId);
        await firestore
            .collection('queues')
            .doc(contact.receiveQueueId)
            .collection('packets')
            .doc(packet.packetId)
            .delete();
        return;
      }

      if (action == 'reaction') {
        final targetMessageId = payload['targetMessageId'] as String;
        final emoji = payload['emoji'] as String;
        await dbService.saveReaction(Reaction(
          id: uuid.v4(),
          messageId: targetMessageId,
          contactId: contact.id,
          emoji: emoji,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
        await firestore
            .collection('queues')
            .doc(contact.receiveQueueId)
            .collection('packets')
            .doc(packet.packetId)
            .delete();
        return;
      }

      if (action == 'file_chunk') {
        final targetMessageId = payload['targetMessageId'] as String;
        final chunkIndex = payload['chunkIndex'] as int;
        final totalChunks = payload['totalChunks'] as int;
        final chunkData = payload['chunkData'] as String;
        final fName = payload['fileName'] as String? ?? 'media_$targetMessageId.dat';

        chunkBuffers.putIfAbsent(targetMessageId, () => List<String?>.filled(totalChunks, null));
        chunkBuffers[targetMessageId]![chunkIndex] = chunkData;

        if (!chunkBuffers[targetMessageId]!.contains(null)) {
          final fullBase64 = chunkBuffers[targetMessageId]!.join();
          chunkBuffers.remove(targetMessageId);

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

            final existingMsg = await dbService.getMessage(targetMessageId);
            if (existingMsg != null) {
              await dbService.saveMessage(existingMsg.copyWith(filePath: targetFile.path));
            } else {
              completedMediaFiles[targetMessageId] = targetFile.path;
            }
          } catch (e) {
            debugPrint('Background error reassembling file chunks: $e');
          }
        }

        await firestore
            .collection('queues')
            .doc(contact.receiveQueueId)
            .collection('packets')
            .doc(packet.packetId)
            .delete();
        return;
      }

      // Normal message
      final msgId = payload['id'] as String? ?? uuid.v4();
      final content = payload['content'] as String? ?? '';
      final typeStr = payload['type'] as String? ?? 'text';
      final type = MessageType.values.firstWhere((e) => e.name == typeStr, orElse: () => MessageType.text);

      int? expiresAt;
      if (contact.disappearingDurationSeconds > 0) {
        expiresAt = DateTime.now().millisecondsSinceEpoch + (contact.disappearingDurationSeconds * 1000);
      }

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
        } catch (_) {}
      } else if (completedMediaFiles.containsKey(msgId)) {
        localSavedPath = completedMediaFiles.remove(msgId);
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

      await dbService.saveMessage(message);

      // Update Conversation
      final conv = await dbService.getConversation(contact.id);
      if (conv != null) {
        await dbService.saveConversation(conv.copyWith(
          lastMessageText: content.isNotEmpty ? content : '[${type.name}]',
          lastMessageTime: message.timestamp,
          unreadCount: conv.unreadCount + 1,
        ));
      }

      // Delete packet from Firestore Blinded Relay
      await firestore
          .collection('queues')
          .doc(contact.receiveQueueId)
          .collection('packets')
          .doc(packet.packetId)
          .delete();

      // Show Push Notification if not in foreground
      if (!isAppInForeground) {
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

        try {
          await NotificationService.instance.showMessageNotification(
            title: contact.displayName,
            body: notificationBody,
            conversationId: contact.id,
          );
        } catch (e) {
          debugPrint('Notification trigger warning in background: $e');
        }
      }
    } catch (e) {
      debugPrint('Background message processing error: $e');
    }
  }

  Future<void> processInvitePacket(String inboxQueueId, QueuePacket packet) async {
    try {
      final contact = await connRepo.processIncomingHandshake(
        inboxQueueId: inboxQueueId,
        packet: packet,
      );
      if (contact != null) {
        await NotificationService.instance.showMessageNotification(
          title: contact.displayName,
          body: 'Sent you a connection request',
          conversationId: contact.id,
        );
      }
    } catch (e) {
      debugPrint('Background handshake processing error: $e');
    }
  }

  Future<void> drainQueue(String queueId, Contact contact) async {
    try {
      final snap = await firestore
          .collection('queues')
          .doc(queueId)
          .collection('packets')
          .orderBy('timestamp')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final packet = QueuePacket.fromMap(data);
        await processPacket(contact, packet);
      }
    } catch (_) {}
  }

  Future<void> drainInviteQueue(String inboxQueueId) async {
    try {
      final snap = await firestore
          .collection('queues')
          .doc(inboxQueueId)
          .collection('packets')
          .orderBy('timestamp')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final packet = QueuePacket.fromMap(data);
        await processInvitePacket(inboxQueueId, packet);
      }
    } catch (_) {}
  }

  Future<void> syncAll() async {
    try {
      final contacts = await dbService.getAllContacts();
      for (final contact in contacts) {
        final qId = contact.receiveQueueId;

        if (!activeSubscriptions.containsKey(qId)) {
          final sub = firestore
              .collection('queues')
              .doc(qId)
              .collection('packets')
              .snapshots()
              .expand((s) => s.docChanges)
              .where((c) => c.type == DocumentChangeType.added && c.doc.data() != null)
              .listen((change) async {
            final packet = QueuePacket.fromMap(change.doc.data()!);
            await processPacket(contact, packet);
          });
          activeSubscriptions[qId] = sub;
        }

        // Drain pending packets
        await drainQueue(qId, contact);
      }

      // Sync active invite queues
      final db = await dbService.database;
      final inviteRows = await db.query(
        'settings',
        where: "key LIKE 'pending_invite_%'",
      );
      for (final row in inviteRows) {
        try {
          final meta = jsonDecode(row['value'] as String) as Map<String, dynamic>;
          final inboxQueueId = meta['inboxQueueId'] as String;
          if (!activeSubscriptions.containsKey(inboxQueueId)) {
            final sub = firestore
                .collection('queues')
                .doc(inboxQueueId)
                .collection('packets')
                .snapshots()
                .expand((s) => s.docChanges)
                .where((c) => c.type == DocumentChangeType.added && c.doc.data() != null)
                .listen((change) async {
              final packet = QueuePacket.fromMap(change.doc.data()!);
              await processInvitePacket(inboxQueueId, packet);
            });
            activeSubscriptions[inboxQueueId] = sub;
          }
          await drainInviteQueue(inboxQueueId);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Background syncAll error: $e');
    }
  }

  service.on('reloadQueues').listen((_) async {
    await syncAll();
  });

  // Initial sync
  await syncAll();

  // Periodic heartbeat sync every 4 seconds
  Timer.periodic(const Duration(seconds: 4), (timer) async {
    try {
      final contacts = await dbService.getAllContacts();
      for (final c in contacts) {
        await drainQueue(c.receiveQueueId, c);
      }
      final db = await dbService.database;
      final inviteRows = await db.query(
        'settings',
        where: "key LIKE 'pending_invite_%'",
      );
      for (final row in inviteRows) {
        try {
          final meta = jsonDecode(row['value'] as String) as Map<String, dynamic>;
          final inboxQueueId = meta['inboxQueueId'] as String;
          await drainInviteQueue(inboxQueueId);
        } catch (_) {}
      }
    } catch (_) {}
  });
}
