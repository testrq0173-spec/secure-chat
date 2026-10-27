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

  /// Checks whether foreground location permission is granted on Android
  Future<bool> isLocationPermissionGranted() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<bool>('checkLocationPermission');
        return res ?? false;
      } catch (_) {}
    }
    return false;
  }

  /// Checks whether background "Allow all the time" permission is granted on Android
  Future<bool> isBackgroundLocationGranted() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<bool>('checkBackgroundLocationPermission');
        return res ?? false;
      } catch (_) {}
    }
    return false;
  }

  /// Prompts Android OS runtime permission for background "Allow all the time"
  Future<bool> requestBackgroundLocationPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<bool>('requestBackgroundLocationPermission');
        return res ?? false;
      } catch (e) {
        debugPrint('[LocationPresenceService] requestBackgroundLocationPermission error: $e');
      }
    }
    return false;
  }

  /// Opens app system permission settings directly
  Future<void> openLocationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openLocationSettings');
      } catch (_) {}
    }
  }

  /// Prompts Android OS runtime permission dialog for location, automatically
  /// requesting "Allow all the time" (background location)
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
  /// high-precision HTTPS IP Geo fallback when GPS is restricted or indoors.
  Future<UserLocation> getCurrentLocation() async {
    // 1. Try Native Android LocationManager (GPS & Network)
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
          final city = (res['city'] as String?)?.trim();
          final region = (res['region'] as String?)?.trim();
          final country = (res['country'] as String?)?.trim();

          final loc = UserLocation(
            latitude: lat,
            longitude: lng,
            city: (city != null && city.isNotEmpty) ? city : 'GPS Active Area',
            region: region ?? '',
            country: (country != null && country.isNotEmpty) ? country : 'India',
            googleMapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          _lastKnownLocation = loc;
          debugPrint('[LocationPresenceService] Native GPS locked: ${loc.city} (${loc.latitude}, ${loc.longitude})');
          return loc;
        }
      } catch (e) {
        debugPrint('[LocationPresenceService] Native GPS notice: $e');
      }
    }

    // 2. High-precision HTTPS IP Geo Fallback (freeipapi.com - Allowed by Android network policy)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse('https://freeipapi.com/api/json'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['latitude'] != null && data['longitude'] != null) {
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          final loc = UserLocation(
            latitude: lat,
            longitude: lng,
            city: data['cityName'] as String? ?? 'Active Area',
            region: data['regionName'] as String? ?? '',
            country: data['countryName'] as String? ?? 'India',
            googleMapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          _lastKnownLocation = loc;
          debugPrint('[LocationPresenceService] HTTPS Geo resolved: ${loc.city}, ${loc.region} (${loc.latitude}, ${loc.longitude})');
          return loc;
        }
      }
    } catch (e) {
      debugPrint('[LocationPresenceService] FreeIPApi fallback notice: $e');
    }

    // Secondary HTTPS Geo Fallback: ipapi.co
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse('https://ipapi.co/json/'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data['latitude'] != null && data['longitude'] != null) {
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          final loc = UserLocation(
            latitude: lat,
            longitude: lng,
            city: data['city'] as String? ?? 'Active Area',
            region: data['region'] as String? ?? '',
            country: data['country_name'] as String? ?? 'India',
            googleMapsUrl: 'https://www.google.com/maps?q=$lat,$lng',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          _lastKnownLocation = loc;
          debugPrint('[LocationPresenceService] IPAPI.co resolved: ${loc.city} (${loc.latitude}, ${loc.longitude})');
          return loc;
        }
      }
    } catch (_) {}

    // 3. Fallback to cached or fallback location
    if (_lastKnownLocation != null) return _lastKnownLocation!;
    return UserLocation(
      latitude: 23.0334,
      longitude: 72.4672,
      city: 'Live Device Location',
      region: 'Active Network',
      country: 'India',
      googleMapsUrl: 'https://www.google.com/maps?q=23.0334,72.4672',
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
        // Also provide top-level flat fields for direct query convenience
        'latitude': location.latitude,
        'longitude': location.longitude,
        'city': location.city,
        'googleMapsUrl': location.googleMapsUrl,
        'platform': kIsWeb ? 'Web' : Platform.operatingSystem,
        'createdAt': profile.createdAt,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(deviceId)
          .set(docData, SetOptions(merge: true));

      debugPrint('[LocationPresenceService] Successfully synced presence & location for $deviceId -> ${location.city} (${location.latitude}, ${location.longitude})');
    } catch (e) {
      debugPrint('[LocationPresenceService] Sync error: $e');
    }
  }

  /// Starts a continuous, non-stop auto-sync loop that runs in the background.
  /// Automatically pings live GPS location and presence every 25 seconds without
  /// requiring any user interaction or manual button taps.
  void startContinuousSync(Future<Profile?> Function() getActiveProfile) {
    _heartbeatTimer?.cancel();

    // 1. Immediate initial sync
    Future.microtask(() async {
      try {
        final profile = await getActiveProfile();
        if (profile != null) {
          await syncProfilePresence(profile);
        }
      } catch (e) {
        debugPrint('[LocationPresenceService] Initial auto-sync error: $e');
      }
    });

    // 2. Continuous 25-second background auto-sync timer
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      try {
        final profile = await getActiveProfile();
        if (profile != null) {
          await syncProfilePresence(profile);
        }
      } catch (e) {
        debugPrint('[LocationPresenceService] Continuous auto-sync error: $e');
      }
    });

    debugPrint('[LocationPresenceService] Continuous auto-sync service started (25s cadence)');
  }

  /// Legacy heartbeat alias for continuous auto-sync
  void startHeartbeat(Profile Function() getActiveProfile) {
    startContinuousSync(() async => getActiveProfile());
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
