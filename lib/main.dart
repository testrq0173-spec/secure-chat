import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'core/services/background_delivery_service.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Notifications
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('NotificationService init notice: $e');
  }

  // Initialize Firebase (safely caught if google-services.json is pending)
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully for real-time sync');
  } catch (e) {
    debugPrint('Firebase init notice: $e (Falling back to local relay)');
  }

  // Initialize Background Delivery Service (WhatsApp-style killed state & background delivery)
  try {
    await BackgroundDeliveryService.instance.initialize();
    debugPrint('BackgroundDeliveryService initialized successfully');
  } catch (e) {
    debugPrint('BackgroundDeliveryService init notice: $e');
  }

  runApp(
    const ProviderScope(
      child: BharosaApp(),
    ),
  );
}
