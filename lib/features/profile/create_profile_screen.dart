import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/providers.dart';
import '../../core/services/device_identity_service.dart';
import '../../core/services/location_presence_service.dart';
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
  final TextEditingController _usernameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _photoPath;
  String? _permanentDeviceId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final devId = await DeviceIdentityService.getPermanentDeviceId();
    if (mounted) {
      setState(() => _permanentDeviceId = devId);
    }
    // Proactively request Android OS location permission so user is prompted
    await LocationPresenceService.instance.requestLocationPermission();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _photoPath = picked.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose Profile Photo',
                style: AppTypography.title.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.lavender,
                  child: Icon(Icons.photo_library_rounded, color: AppColors.ultraviolet),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.lavender,
                  child: Icon(Icons.camera_alt_rounded, color: AppColors.ultraviolet),
                ),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFEBEE),
                    child: Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _photoPath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createProfile({bool skipLock = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a display name')),
      );
      return;
    }

    final username = _usernameController.text.trim();

    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.createInitialProfile(
        displayName: name,
        username: username.isNotEmpty ? username : null,
        photoPath: _photoPath,
      );

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
        title: const Text('Setup Vault Profile'),
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
                'Create Your Identity',
                style: AppTypography.display.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'Your User ID is permanently bound to this physical device. You can customize your name, username handle, and avatar anytime.',
                style: AppTypography.caption.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 32),

              // Avatar with Photo Pick Overlay
              Center(
                child: GestureDetector(
                  onTap: _showPhotoOptions,
                  child: Stack(
                    children: [
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _nameController,
                        builder: (context, value, _) {
                          return AppAvatar(
                            name: value.text.isEmpty ? 'User' : value.text,
                            imageUrl: _photoPath,
                            radius: 50,
                          );
                        },
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.ultraviolet,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.white, width: 2),
                            boxShadow: AppColors.softCardShadow,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: AppColors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _showPhotoOptions,
                  child: Text(
                    _photoPath != null ? 'Change Photo' : 'Add Profile Photo',
                    style: AppTypography.button.copyWith(
                      color: AppColors.ultraviolet,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Full / Display Name Field
              Text(
                'Full / Display Name',
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Rahul Sharma, Phoenix, 0xAnon',
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.grey500),
                  suffixIcon: _nameController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.grey500),
                          onPressed: () => _nameController.clear(),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 20),

              // Username Handle Field
              Text(
                'Username Handle (Optional)',
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  hintText: 'e.g. rahul_18, cryptoknight',
                  prefixIcon: Icon(Icons.alternate_email_rounded, color: AppColors.grey500),
                ),
              ),

              const SizedBox(height: 24),

              // Permanent Device ID Badge
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.fingerprint_rounded, color: AppColors.ultraviolet, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'PERMANENT DEVICE ID',
                          style: AppTypography.caption.copyWith(
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: AppColors.grey500,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.ultraviolet.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'HARDWARE BOUND',
                            style: AppTypography.caption.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ultraviolet,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _permanentDeviceId ?? 'Detecting hardware ID...',
                            style: AppTypography.caption.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (_permanentDeviceId != null)
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.grey500),
                            tooltip: 'Copy Permanent Device ID',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _permanentDeviceId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Permanent Device ID copied!')),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This permanent ID is generated from your device hardware. World mein har device ki unique ID hoti hai, so your account identity is locked to this physical device.',
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.grey500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

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
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => context.push('/restore-account'),
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                  label: const Text('I already have an account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ultraviolet,
                    side: const BorderSide(color: AppColors.lavender),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

