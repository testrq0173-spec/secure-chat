import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../data/local/database_service.dart';
import 'notification_service.dart';

/// Top-level background message handler invoked by Google Play Services
/// even when the application is completely killed or swiped away from recent apps.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'AIzaSyCRbr12prX64vf9cfUtI4xiqSpMXjUABSU',
            appId: '1:361674096094:web:bcd1690b21d8713b97314f',
            messagingSenderId: '361674096094',
            projectId: 'bharosa-chat',
            storageBucket: 'bharosa-chat.firebasestorage.app',
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
    }

    await NotificationService.instance.initialize();

    final data = message.data;
    final queueId = data['queueId'] as String?;

    String title = data['title'] as String? ?? message.notification?.title ?? 'Bharosa';
    String body = data['body'] as String? ?? message.notification?.body ?? 'New encrypted message received';
    String conversationId = queueId ?? 'general';

    // Local contact lookup: If we recognize the receiveQueueId, personalize the notification
    if (queueId != null && queueId.isNotEmpty) {
      try {
        final dbService = DatabaseService();
        final contact = await dbService.getContactByReceiveQueue(queueId);
        if (contact != null) {
          title = contact.displayName;
          body = 'New encrypted message';
          conversationId = contact.id;
        }
      } catch (_) {}
    }

    await NotificationService.instance.showMessageNotification(
      title: title,
      body: body,
      conversationId: conversationId,
    );
  } catch (e) {
    debugPrint('FCM background handler notice: $e');
  }
}

/// Manages WhatsApp-style FCM push notification lifecycle and device token synchronization.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _cachedToken;

  /// Retrieves the current device registration token from Google Play Services (FCM).
  Future<String?> getDeviceToken() async {
    if (kIsWeb) return null;
    if (_cachedToken != null) return _cachedToken;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // ignore: deprecated_member_use
        _cachedToken = await FirebaseMessaging.instance.getToken();
        return _cachedToken;
      }
    } catch (e) {
      debugPrint('FCM token retrieval notice: $e');
    }
    return null;
  }

  /// Initializes FCM listeners, permissions, and token refresh hooks.
  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permissions
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('FCM permission authorizationStatus: ${settings.authorizationStatus}');

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Cache device token
      // ignore: deprecated_member_use
      _cachedToken = await messaging.getToken();
      if (_cachedToken != null) {
        debugPrint('FCM Device Token registered: ${_cachedToken!.substring(0, 12)}...');
      }

      // Handle foreground notifications (show heads-up banner)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final data = message.data;
        if (notification != null) {
          NotificationService.instance.showMessageNotification(
            title: notification.title ?? 'Bharosa',
            body: notification.body ?? 'New encrypted message',
            conversationId: data['queueId'] as String? ?? 'general',
          );
        }
      });

      // Handle token rotation
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        debugPrint('FCM Device Token refreshed');
      });
    } catch (e) {
      debugPrint('PushNotificationService initialization error: $e');
    }
  }

  /// Registers or updates the device's FCM token on a specific Firestore queue document.
  Future<void> attachTokenToQueue(String queueId) async {
    if (kIsWeb) return;
    try {
      final token = await getDeviceToken();
      if (token == null || token.isEmpty) return;

      await FirebaseFirestore.instance.collection('queues').doc(queueId).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to attach FCM token to queue $queueId: $e');
    }
  }

  /// Syncs the FCM token to all active receiving queues for the user.
  Future<void> syncTokensForQueues(List<String> queueIds) async {
    if (kIsWeb || queueIds.isEmpty) return;
    try {
      final token = await getDeviceToken();
      if (token == null || token.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final qId in queueIds) {
        if (qId.isNotEmpty) {
          final docRef = FirebaseFirestore.instance.collection('queues').doc(qId);
          batch.set(docRef, {
            'fcmToken': token,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      await batch.commit();
      debugPrint('Synced FCM token to ${queueIds.length} queues');
    } catch (e) {
      debugPrint('Failed to batch sync FCM tokens: $e');
    }
  }
}
