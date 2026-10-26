import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';

class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  ConsumerState<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createProfile({bool skipLock = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a display name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.createInitialProfile(displayName: name);

      // Create initial Saved Notes conversation
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.getOrCreateSavedNotes();

      if (!mounted) return;
      if (skipLock) {
        context.go('/home');
      } else {
        context.go('/set-lock');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize keys: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Setup Vault'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => _createProfile(skipLock: true),
            child: Text(
              'Skip',
              style: AppTypography.button.copyWith(
                color: AppColors.grey500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a Display Name',
                style: AppTypography.display.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'No phone number or email required. This display name will be encrypted and shared only when you connect with someone.',
                style: AppTypography.caption.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 36),

              // Avatar Preview
              Center(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _nameController,
                  builder: (context, value, _) {
                    return AppAvatar(
                      name: value.text.isEmpty ? 'User' : value.text,
                      radius: 46,
                    );
                  },
                ),
              ),
              const SizedBox(height: 36),

              // Display Name Field
              Text(
                'Display Name',
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Alice, Phoenix, 0xAnon',
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.grey500),
                  suffixIcon: _nameController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.grey500),
                          onPressed: () => _nameController.clear(),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 24),

              // Zero-Knowledge Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lavender.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.lavender),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_rounded, color: AppColors.ultraviolet, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your cryptographic Ed25519 and X25519 identity keypairs are created directly inside this device’s hardware vault.',
                        style: AppTypography.caption.copyWith(color: AppColors.ink, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // Submit Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _createProfile(skipLock: false),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                        )
                      : const Text('Continue to App Lock'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isLoading ? null : () => _createProfile(skipLock: true),
                  child: Text(
                    'Skip App Lock',
                    style: AppTypography.button.copyWith(
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
