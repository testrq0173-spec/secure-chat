import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/services/biometric_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/passcode_keypad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _isError = false;
  final BiometricService _biometricService = BiometricService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBiometric();
    });
  }

  Future<void> _checkAutoBiometric() async {
    final lockState = ref.read(appLockProvider);
    if (lockState.isBiometricEnabled) {
      _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    final status = await _biometricService.checkEnrollmentStatus();
    if (status == BiometricEnrollmentStatus.notEnrolled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable your phone's fingerprint/facelock in device Settings")),
        );
      }
      return;
    }

    if (status == BiometricEnrollmentStatus.available) {
      final authenticated = await _biometricService.authenticate(
        reason: 'Authenticate to unlock your encrypted Bharosa vault',
      );
      if (authenticated) {
        ref.read(appLockProvider.notifier).unlock();
        if (mounted) context.go('/home');
      }
    }
  }

  void _onPinEntered(String pin) async {
    final notifier = ref.read(appLockProvider.notifier);
    final success = await notifier.verifyAndUnlock(pin);

    if (success) {
      if (!mounted) return;
      context.go('/home');
    } else {
      setState(() => _isError = true);
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _isError = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Center(
            child: PasscodeKeypad(
              title: 'Vault Locked',
              subtitle: 'Enter your 4-digit PIN to access encrypted chats',
              pinLength: 4,
              showBiometric: lockState.isBiometricEnabled,
              isError: _isError,
              onBiometricTap: _tryBiometricUnlock,
              onPinComplete: _onPinEntered,
            ),
          ),
        ),
      ),
    );
  }
}
