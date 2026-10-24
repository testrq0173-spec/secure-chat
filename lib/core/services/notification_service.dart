import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification click if needed
      },
    );

    // Request Android 13+ notification permission
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    _isInitialized = true;
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    required String conversationId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'bharosa_messages',
      'Encrypted Messages',
      channelDescription: 'Real-time notifications for incoming encrypted messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.show(
      id: conversationId.hashCode,
      title: title,
      body: body.isNotEmpty ? body : '🔒 New encrypted message',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: conversationId,
    );

  }
}
