import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class PasscodeKeypad extends StatefulWidget {
  final String title;
  final String subtitle;
  final int pinLength;
  final bool showBiometric;
  final VoidCallback? onBiometricTap;
  final Function(String pin) onPinComplete;
  final bool isError;

  const PasscodeKeypad({
    super.key,
    required this.title,
    this.subtitle = 'Enter passcode to unlock your vault',
    this.pinLength = 4,
    this.showBiometric = false,
    this.onBiometricTap,
    required this.onPinComplete,
    this.isError = false,
  });

  @override
  State<PasscodeKeypad> createState() => _PasscodeKeypadState();
}

class _PasscodeKeypadState extends State<PasscodeKeypad> with SingleTickerProviderStateMixin {
  String _currentPin = '';
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void didUpdateWidget(covariant PasscodeKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != oldWidget.title) {
      setState(() => _currentPin = '');
    }
    if (widget.isError && !oldWidget.isError) {
      _shakeController.forward(from: 0.0).then((_) {
        setState(() => _currentPin = '');
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_currentPin.length < widget.pinLength) {
      setState(() {
        _currentPin += digit;
      });
      if (_currentPin.length == widget.pinLength) {
        widget.onPinComplete(_currentPin);
      }
    }
  }

  void _onBackspace() {
    if (_currentPin.isNotEmpty) {
      setState(() {
        _currentPin = _currentPin.substring(0, _currentPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.ultraviolet),
        const SizedBox(height: 16),
        Text(widget.title, style: AppTypography.title.copyWith(fontSize: 22)),
        const SizedBox(height: 8),
        Text(widget.subtitle, style: AppTypography.caption),
        const SizedBox(height: 32),

        // Dots Indicator
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final offset = 12 * (1 - _shakeController.value) *
                (1 - _shakeController.value) *
                (widget.isError ? 1 : 0);
            return Transform.translate(
              offset: Offset(offset, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.pinLength,
                  (index) {
                    final filled = index < _currentPin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? (widget.isError ? AppColors.error : AppColors.ultraviolet)
                            : AppColors.lavender.withValues(alpha: 0.4),
                        border: Border.all(
                          color: filled
                              ? (widget.isError ? AppColors.error : AppColors.ultraviolet)
                              : AppColors.grey200,
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 48),

        // Keypad Grid
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            children: [
              _buildRow(['1', '2', '3']),
              const SizedBox(height: 20),
              _buildRow(['4', '5', '6']),
              const SizedBox(height: 20),
              _buildRow(['7', '8', '9']),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Biometric or empty
                  if (widget.showBiometric)
                    _keyButton(
                      child: const Icon(Icons.fingerprint_rounded, size: 28, color: AppColors.ultraviolet),
                      onTap: widget.onBiometricTap,
                    )
                  else
                    const SizedBox(width: 64, height: 64),

                  _numberButton('0'),

                  _keyButton(
                    child: const Icon(Icons.backspace_outlined, size: 24, color: AppColors.ink),
                    onTap: _onBackspace,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: digits.map((d) => _numberButton(d)).toList(),
    );
  }

  Widget _numberButton(String digit) {
    return _keyButton(
      child: Text(
        digit,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.ink),
      ),
      onTap: () => _onDigit(digit),
    );
  }

  Widget _keyButton({required Widget child, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          boxShadow: AppColors.softCardShadow,
          border: Border.all(color: AppColors.grey200.withValues(alpha: 0.6)),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
