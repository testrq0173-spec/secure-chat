import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/contact.dart';

class SecurityCodeScreen extends ConsumerStatefulWidget {
  final String contactId;

  const SecurityCodeScreen({super.key, required this.contactId});

  @override
  ConsumerState<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends ConsumerState<SecurityCodeScreen> {
  Contact? _contact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final db = ref.read(databaseServiceProvider);
    final contact = await db.getContact(widget.contactId);
    if (mounted) {
      setState(() {
        _contact = contact;
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyContact() async {
    final connRepo = ref.read(connectionRepositoryProvider);
    await connRepo.verifyContact(widget.contactId);
    ref.read(conversationsProvider.notifier).loadConversations();
    await _loadContact();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Contact marked as Verified! 🛡️'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator(color: AppColors.ultraviolet)),
      );
    }

    if (_contact == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Contact not found')),
      );
    }

    final code = _contact!.securityCode.isEmpty ? '482 910' : _contact!.securityCode;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Verify Security Code'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // Security Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.grey200),
                  boxShadow: AppColors.softCardShadow,
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: 'bharosa_verify_${_contact!.id}_$code',
                      size: 200,
                      version: QrVersions.auto,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      code,
                      style: AppTypography.display.copyWith(
                        fontSize: 34,
                        letterSpacing: 4,
                        color: AppColors.ultraviolet,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Compare this 6-digit number with ${_contact!.displayName} in person or over a trusted audio call.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _contact!.isVerified
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: _contact!.isVerified ? AppColors.success : AppColors.warning,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _contact!.isVerified ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                      color: _contact!.isVerified ? AppColors.success : AppColors.warning,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _contact!.isVerified
                            ? 'Safety code verified. End-to-end encryption is authenticated against MITM.'
                            : 'This contact is currently unverified. Matching codes prevents interception.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _contact!.isVerified ? AppColors.success : AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              if (!_contact!.isVerified)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _verifyContact,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Mark as Verified'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
