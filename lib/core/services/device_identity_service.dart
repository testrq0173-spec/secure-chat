import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Service responsible for deriving and persisting a hardware-bound permanent Device ID.
/// On Android, this uses the hardware Settings.Secure.ANDROID_ID which remains constant
/// across app uninstalls and reinstalls for the same app signature.
class DeviceIdentityService {
  static const MethodChannel _channel = MethodChannel('com.bharosa.app/screen_protector');
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _kPermanentDeviceId = 'bharosa_permanent_device_id';
  static const Uuid _uuid = Uuid();

  static String? _cachedPermanentId;

  /// Retrieves the permanent unique device-based User ID.
  /// Format: `dev_<hardware_id>` (e.g. `dev_9774d56d682e549c`)
  static Future<String> getPermanentDeviceId() async {
    if (_cachedPermanentId != null && _cachedPermanentId!.isNotEmpty) {
      return _cachedPermanentId!;
    }

    String? hardwareId;

    // 1. Try reading native hardware device ID on Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final id = await _channel.invokeMethod<String>('getDeviceId');
        if (id != null && id.trim().isNotEmpty) {
          hardwareId = id.trim().toLowerCase();
        }
      } catch (e) {
        debugPrint('[DeviceIdentityService] Platform channel getDeviceId error: $e');
      }
    }

    // 2. If no hardware ID from platform, try Secure Storage & SharedPreferences
    if (hardwareId == null || hardwareId.isEmpty) {
      try {
        final stored = await _secureStorage.read(key: _kPermanentDeviceId);
        if (stored != null && stored.trim().isNotEmpty) {
          hardwareId = stored.trim().toLowerCase();
        }
      } catch (_) {}
    }

    if (hardwareId == null || hardwareId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString(_kPermanentDeviceId);
        if (stored != null && stored.trim().isNotEmpty) {
          hardwareId = stored.trim().toLowerCase();
        }
      } catch (_) {}
    }

    // 3. Fallback: Generate a persistent UUID seed if none exists
    if (hardwareId == null || hardwareId.isEmpty) {
      hardwareId = _uuid.v4().replaceAll('-', '').toLowerCase().substring(0, 16);
    }

    // Clean any unwanted symbols
    final cleanId = hardwareId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final permanentId = cleanId.startsWith('dev_') ? cleanId : 'dev_$cleanId';

    // 4. Persist in both Secure Storage and SharedPreferences for permanence
    try {
      await _secureStorage.write(key: _kPermanentDeviceId, value: permanentId);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPermanentDeviceId, permanentId);
    } catch (_) {}

    _cachedPermanentId = permanentId;
    return permanentId;
  }

  /// Clears in-memory cache (for testing or profile resets)
  static void clearCache() {
    _cachedPermanentId = null;
  }
}
