import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricEnrollmentStatus {
  available,
  notSupported,
  notEnrolled,
}

class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  /// Checks if device has biometric hardware and if the user has enrolled fingerprint/face
  Future<BiometricEnrollmentStatus> checkEnrollmentStatus() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        return BiometricEnrollmentStatus.notSupported;
      }

      final canCheck = await _auth.canCheckBiometrics;
      final availableBiometrics = await _auth.getAvailableBiometrics();

      if (!canCheck || availableBiometrics.isEmpty) {
        return BiometricEnrollmentStatus.notEnrolled;
      }

      return BiometricEnrollmentStatus.available;
    } on PlatformException {
      return BiometricEnrollmentStatus.notEnrolled;
    } catch (_) {
      return BiometricEnrollmentStatus.notSupported;
    }
  }

  /// Triggers the system biometric prompt
  Future<bool> authenticate({String reason = 'Authenticate to access your Bharosa vault'}) async {
    try {
      final status = await checkEnrollmentStatus();
      if (status != BiometricEnrollmentStatus.available) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
