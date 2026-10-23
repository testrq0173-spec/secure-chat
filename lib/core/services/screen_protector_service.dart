import 'package:flutter/services.dart';

class ScreenProtectorService {
  ScreenProtectorService._();

  static const MethodChannel _channel = MethodChannel('com.bharosa.app/screen_protector');

  /// Blocks screenshots and screen recording by setting FLAG_SECURE on Android window
  static Future<bool> setSecure(bool enable) async {
    try {
      final method = enable ? 'enableSecure' : 'disableSecure';
      final res = await _channel.invokeMethod<bool>(method);
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
