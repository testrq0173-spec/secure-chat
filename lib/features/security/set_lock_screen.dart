import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/passcode_keypad.dart';

class SetLockScreen extends ConsumerStatefulWidget {
  const SetLockScreen({super.key});

  @override
  ConsumerState<SetLockScreen> createState() => _SetLockScreenState();
}

class _SetLockScreenState extends ConsumerState<SetLockScreen> {
  String? _firstPin;
  bool _isConfirming = false;
  bool _isError = false;

  void _onPinEntered(String pin) async {
    if (!_isConfirming) {
      setState(() {
        _firstPin = pin;
        _isConfirming = true;
      });
    } else {
      if (pin == _firstPin) {
        // PIN matched!
        final storage = ref.read(secureStorageProvider);
        await storage.setAppPin(pin);
        ref.read(appLockProvider.notifier).refresh();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN configured successfully!')),
        );
        context.go('/home');
      } else {
        // Mismatch
        setState(() {
          _isError = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PINs do not match. Please try again.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 2),
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          setState(() {
            _firstPin = null;
            _isConfirming = false;
            _isError = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('Skip', style: AppTypography.button.copyWith(color: AppColors.grey500)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: PasscodeKeypad(
            key: ValueKey('keypad_step_${_isConfirming ? "confirm" : "set"}_${_firstPin ?? "none"}'),
            title: _isConfirming ? 'Confirm PIN' : 'Set App Lock',
            subtitle: _isConfirming
                ? 'Re-enter your 4-digit PIN to confirm'
                : 'Protect your encrypted local database with a PIN',
            pinLength: 4,
            isError: _isError,
            onPinComplete: _onPinEntered,
          ),
        ),
      ),
    );
  }
}
