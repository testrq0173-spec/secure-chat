import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../data/models/profile.dart';
import 'device_identity_service.dart';

class UserLocation {
  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String country;
  final String googleMapsUrl;
  final int updatedAt;

  UserLocation({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.region,
    required this.country,
    required this.googleMapsUrl,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'region': region,
      'country': country,
      'googleMapsUrl': googleMapsUrl,
      'updatedAt': updatedAt,
    };
  }

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    final lat = (map['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (map['longitude'] as num?)?.toDouble() ?? 0.0;
    return UserLocation(
      latitude: lat,
      longitude: lng,
      city: map['city'] as String? ?? 'Unknown',
      region: map['region'] as String? ?? '',
      country: map['country'] as String? ?? '',
      googleMapsUrl: map['googleMapsUrl'] as String? ?? 'https://www.google.com/maps?q=$lat,$lng',
      updatedAt: map['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Service that coordinates device live location tracking and real-time
/// presence synchronization with Firestore for the Web Admin Panel.
class LocationPresenceService {
  static final LocationPresenceService instance = LocationPresenceService._internal();
  LocationPresenceService._internal();

  static const MethodChannel _channel = MethodChannel('com.bharosa.app/screen_protector');
  Timer? _heartbeatTimer;
  UserLocation? _lastKnownLocation;

  /// Checks whether location permission is granted on Android
  Future<bool> isLocationPermissionGranted() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<bool>('checkLocationPermission');
        return res ?? false;
      } catch (_) {}
    }
    return false;
  }

  /// Prompts Android OS runtime permission dialog for fine/coarse location
  Future<bool> requestLocationPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<bool>('requestLocationPermission');
        return res ?? false;
      } catch (e) {
        debugPrint('[LocationPresenceService] requestLocationPermission error: $e');
      }
    }
    return false;
  }

  /// Retrieves current location using native GPS hardware, with automatic
  /// high-precision IP Geo fallback when GPS is restricted or on emulator/desktop.
  Future<UserLocation> getCurrentLocation() async {
    // 1. Try Native Android LocationManager
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final hasPerm = await isLocationPermissionGranted();
        if (!hasPerm) {
          await requestLocationPermission();
        }
        final res = await _channel.invokeMethod<Map>('getLocation');
        if (res != null && res['latitude'] != null && res['longitude'] != null) {
          final lat = (res['latitude'] as num).toDouble();
          final lng = (res['longitude'] as num).toDouble();
          final loc = UserLocation(
            latitude: lat,
            longitude: lng,
            city: 'GPS Locked Area',
            region: 'Android Hardware',
            country: 'Active Device',
            googleMapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          _lastKnownLocation = loc;
          return loc;
        }
      } catch (e) {
        debugPrint('[LocationPresenceService] Native GPS notice: $e');
      }
    }

    // 2. High-precision IP Geo Fallback (no external API keys needed)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse('http://ip-api.com/json'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num).toDouble();
          final lng = (data['lon'] as num).toDouble();
          final loc = UserLocation(
            latitude: lat,
            longitude: lng,
            city: data['city'] as String? ?? 'Unknown City',
            region: data['regionName'] as String? ?? '',
            country: data['country'] as String? ?? '',
            googleMapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          _lastKnownLocation = loc;
          return loc;
        }
      }
    } catch (e) {
      debugPrint('[LocationPresenceService] IP Geo fallback notice: $e');
    }

    // 3. Fallback to cached or default
    if (_lastKnownLocation != null) return _lastKnownLocation!;
    return UserLocation(
      latitude: 28.6139,
      longitude: 77.2090,
      city: 'Delhi (Default)',
      region: 'Delhi',
      country: 'India',
      googleMapsUrl: 'https://www.google.com/maps?q=28.6139,77.2090',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Syncs the profile details and current live location to Firestore
  /// under collection `users/{deviceId}`.
  Future<void> syncProfilePresence(Profile profile) async {
    try {
      final location = await getCurrentLocation();
      final deviceId = await DeviceIdentityService.getPermanentDeviceId();

      String? photoBase64;
      if (profile.photoPath != null && profile.photoPath!.isNotEmpty) {
        try {
          final file = File(profile.photoPath!);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.length <= 150 * 1024) { // Only embed small avatar thumbnails
              photoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
            }
          }
        } catch (_) {}
      }

      final docData = <String, dynamic>{
        'deviceId': deviceId,
        'displayName': profile.displayName,
        'username': profile.username ?? '',
        'photoBase64': photoBase64,
        'isOnline': true,
        'lastActive': FieldValue.serverTimestamp(),
        'lastActiveMillis': DateTime.now().millisecondsSinceEpoch,
        'location': location.toMap(),
        'platform': kIsWeb ? 'Web' : Platform.operatingSystem,
        'createdAt': profile.createdAt,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(deviceId)
          .set(docData, SetOptions(merge: true));

      debugPrint('[LocationPresenceService] Successfully synced presence & location for $deviceId');
    } catch (e) {
      debugPrint('[LocationPresenceService] Sync error: $e');
    }
  }

  /// Starts a periodic 60-second presence heartbeat while the app is active
  void startHeartbeat(Profile Function() getActiveProfile) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final profile = getActiveProfile();
        await syncProfilePresence(profile);
      } catch (_) {}
    });
  }

  /// Stops heartbeat and marks user offline
  Future<void> setOffline(String deviceId) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await FirebaseFirestore.instance.collection('users').doc(deviceId).update({
        'isOnline': false,
        'lastActiveMillis': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }
}
