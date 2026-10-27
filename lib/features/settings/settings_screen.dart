import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../app/providers.dart';
import '../../core/crypto/crypto_utils.dart';
import '../../core/crypto/mnemonic_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/screen_protector_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../data/models/profile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isScreenshotBlocked = false;
  bool _isIncognito = false;
  String? _publicKeyFingerprint;

  // WhatsApp-style Backup State
  int? _lastBackupTime;
  int? _lastBackupSize;
  bool _isAutoBackup = true;
  bool _isBackingUp = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = ref.read(secureStorageProvider);
    final authRepo = ref.read(authRepositoryProvider);

    final screenshot = await storage.isScreenshotBlocked();
    final incognito = await storage.isIncognito();
    final pubKey = await authRepo.getIdentityPublicKey();
    final fp = CryptoUtils.toHex(CryptoUtils.sha256(pubKey)).substring(0, 16).toUpperCase();
    final lastTime = await storage.getLastBackupTime();
    final lastSize = await storage.getLastBackupSize();
    final autoBackup = await storage.isAutoBackupEnabled();

    if (mounted) {
      setState(() {
        _isScreenshotBlocked = screenshot;
        _isIncognito = incognito;
        _publicKeyFingerprint = fp;
        _lastBackupTime = lastTime;
        _lastBackupSize = lastSize;
        _isAutoBackup = autoBackup;
      });
    }
  }

  void _showEditProfileDialog(Profile profile) {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final userCtrl = TextEditingController(text: profile.username ?? '');
    String? localPhoto = profile.photoPath;
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Edit Profile', style: AppTypography.title.copyWith(fontSize: 20)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Stack(
                    children: [
                      AppAvatar(
                        name: nameCtrl.text.isEmpty ? 'User' : nameCtrl.text,
                        imageUrl: localPhoto,
                        radius: 46,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: () async {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 512,
                              maxHeight: 512,
                              imageQuality: 85,
                            );
                            if (picked != null) {
                              setModalState(() => localPhoto = picked.path);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.ultraviolet,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, color: AppColors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 512,
                        maxHeight: 512,
                        imageQuality: 85,
                      );
                      if (picked != null) {
                        setModalState(() => localPhoto = picked.path);
                      }
                    },
                    child: const Text('Change Photo', style: TextStyle(color: AppColors.ultraviolet, fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Display / Full Name', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Enter your name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Username Handle', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. rahul_18',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                // Permanent Device ID View
                Container(
                  padding: const EdgeInsets.all(12),
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
                          const Icon(Icons.lock_rounded, size: 14, color: AppColors.grey500),
                          const SizedBox(width: 6),
                          Text(
                            'PERMANENT DEVICE ID (HARDWARE BOUND)',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.grey500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.id,
                        style: AppTypography.caption.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'This ID is permanently bound to this physical device hardware.',
                        style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newName = nameCtrl.text.trim();
                      if (newName.isEmpty) return;
                      final newUsername = userCtrl.text.trim();
                      await ref.read(authRepositoryProvider).updateProfile(
                        displayName: newName,
                        username: newUsername,
                        photoPath: localPhoto,
                      );
                      ref.invalidate(activeProfileProvider);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile updated successfully!')),
                        );
                      }
                    },
                    child: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmEmergencyWipe() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Emergency Vault Wipe'),
          content: const Text(
            'This will permanently delete all private keys, contacts, and encrypted chats from this phone. This action CANNOT be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.pop(ctx);
                final db = ref.read(databaseServiceProvider);
                final storage = ref.read(secureStorageProvider);
                await db.clearAll();
                await storage.wipeAllKeys();

                if (!mounted) return;
                context.go('/onboarding');
              },
              child: const Text('Wipe Everything'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _promptPinVerification() async {
    final pinCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Security Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your 4-digit vault PIN to access your recovery phrase:'),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(letterSpacing: 8, fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: '••••'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final valid = await ref.read(secureStorageProvider).verifyAppPin(pinCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx, valid);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _viewRecoveryPhrase() async {
    final isPinSet = await ref.read(secureStorageProvider).isPinSet();
    if (isPinSet) {
      final ok = await _promptPinVerification();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN verification failed')),
          );
        }
        return;
      }
    }

    final authRepo = ref.read(authRepositoryProvider);
    var phrase = await authRepo.getRecoveryPhrase();
    if (phrase == null || phrase.isEmpty) {
      phrase = MnemonicService.generateMnemonic();
      await ref.read(secureStorageProvider).saveRecoveryPhrase(phrase);
    }

    if (!mounted) return;
    final words = phrase.split(' ');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.grey200, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.vpn_key_rounded, color: AppColors.ultraviolet, size: 24),
                const SizedBox(width: 10),
                Text('Your Secret Recovery Phrase', style: AppTypography.display.copyWith(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Write these 12 words down and store them safely. Anyone with these words can restore and access your identity on a new phone.',
              style: AppTypography.caption.copyWith(color: AppColors.grey500),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(words.length, (i) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.lavender.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.lavender),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${i + 1}. ', style: const TextStyle(color: AppColors.grey500, fontSize: 12)),
                      Text(words[i], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phrase!));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recovery phrase copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy to Clipboard'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _runImmediateBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      final file = await backupService.exportAutoBackup();
      final stat = await file.stat();

      if (!mounted) return;
      setState(() {
        _lastBackupTime = DateTime.now().millisecondsSinceEpoch;
        _lastBackupSize = stat.size;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Backup complete! Saved in Secure Media Vault (Android/media)'),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _exportBackup() async {
    final pwdCtrl = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Export Encrypted Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set a passphrase to encrypt your backup file. A system save dialog will open so you can save it directly to Downloads, Google Drive, or SD card.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pwdCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'Enter backup passphrase',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose Save Location & Export'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && pwdCtrl.text.trim().isNotEmpty) {
      try {
        final backupService = ref.read(backupServiceProvider);
        final file = await backupService.exportEncryptedBackup(
          passphrase: pwdCtrl.text.trim(),
          saveWithSystemDialog: true,
        );
        final stat = await file.stat();
        final sizeKb = (stat.size / 1024).toStringAsFixed(1);

        if (!mounted) return;
        setState(() {
          _lastBackupTime = DateTime.now().millisecondsSinceEpoch;
          _lastBackupSize = stat.size;
        });

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 8),
                Text('Backup Exported!'),
              ],
            ),
            content: Text(
              'Your encrypted backup has been saved successfully:\n\n'
              '📁 ${file.path}\n'
              '📦 Size: $sizeKb KB\n\n'
              'Keep your backup passphrase safe. Without it, the file cannot be decrypted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(activeProfileProvider);
    final appLock = ref.watch(appLockProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Profile Card
            profileAsync.when(
              data: (profile) {
                final name = profile?.displayName ?? 'Anonymous';
                final username = profile?.username;
                final deviceId = profile?.id ?? '...';
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.grey200),
                    boxShadow: AppColors.softCardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppAvatar(
                            name: name,
                            imageUrl: profile?.photoPath,
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTypography.title.copyWith(fontSize: 17)),
                                if (username != null && username.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    '@$username',
                                    style: const TextStyle(
                                      color: AppColors.ultraviolet,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  'Key ID: ${_publicKeyFingerprint ?? "..."}',
                                  style: AppTypography.caption.copyWith(fontFamily: 'monospace', fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (profile != null)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.ultraviolet),
                              tooltip: 'Edit Profile',
                              onPressed: () => _showEditProfileDialog(profile),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      // Permanent Device ID Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.fingerprint_rounded, size: 16, color: AppColors.grey500),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'DEVICE ID',
                                        style: AppTypography.caption.copyWith(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.grey500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.ultraviolet.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'PERMANENT',
                                          style: AppTypography.caption.copyWith(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ultraviolet,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    deviceId,
                                    style: AppTypography.caption.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.grey500),
                              tooltip: 'Copy Permanent Device ID',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: deviceId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Permanent Device ID copied!')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            _sectionHeader('PRIVACY & INCOGNITO'),
            _buildContainer([
              SwitchListTile(
                title: const Text('Incognito Mode'),
                subtitle: const Text('Present isolated pseudonyms for each contact'),
                value: _isIncognito,
                activeThumbColor: AppColors.ultraviolet,
                onChanged: (val) async {
                  setState(() => _isIncognito = val);
                  await ref.read(secureStorageProvider).setIncognito(val);
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Block Screenshots'),
                subtitle: const Text('Prevent screenshots and blur recent apps screen'),
                value: _isScreenshotBlocked,
                activeThumbColor: AppColors.ultraviolet,
                onChanged: (val) async {
                  setState(() => _isScreenshotBlocked = val);
                  await ref.read(secureStorageProvider).setScreenshotBlock(val);
                  await ScreenProtectorService.setSecure(val);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? 'Screenshot & screen recording blocked' : 'Screenshot protection disabled'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ]),

            const SizedBox(height: 24),

            _sectionHeader('APP LOCK & SECURITY'),
            _buildContainer([
              ListTile(
                title: const Text('PIN Protection'),
                subtitle: Text(appLock.isPinSet ? '4-digit PIN is active' : 'No PIN configured'),
                trailing: TextButton(
                  onPressed: () => context.push('/set-lock'),
                  child: Text(appLock.isPinSet ? 'Change' : 'Set PIN'),
                ),
              ),
              if (appLock.isPinSet) ...[
                const Divider(),
                SwitchListTile(
                  title: const Text('Biometric Unlock'),
                  subtitle: const Text('Unlock vault with Fingerprint or Face ID'),
                  value: appLock.isBiometricEnabled,
                  activeThumbColor: AppColors.ultraviolet,
                  onChanged: (val) async {
                    if (val) {
                      final bioService = BiometricService();
                      final status = await bioService.checkEnrollmentStatus();

                      if (!context.mounted) return;

                      if (status == BiometricEnrollmentStatus.notSupported) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Your device hardware does not support biometric authentication.'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      if (status == BiometricEnrollmentStatus.notEnrolled) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.fingerprint_rounded, color: AppColors.ultraviolet, size: 28),
                                SizedBox(width: 10),
                                Text('Biometrics Not Set Up', style: TextStyle(fontSize: 18)),
                              ],
                            ),
                            content: const Text(
                              'Please enable your phone\'s fingerprint or face lock in your device Settings first.',
                              style: TextStyle(fontSize: 15),
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Got it'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      // Authenticate to verify before turning ON
                      final success = await bioService.authenticate(
                        reason: 'Verify your fingerprint or face to enable biometric unlock',
                      );

                      if (success) {
                        await ref.read(secureStorageProvider).setBiometricsEnabled(true);
                        ref.read(appLockProvider.notifier).refresh();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fingerprint / Face unlock enabled successfully!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Biometric verification cancelled.'),
                          ),
                        );
                      }
                    } else {
                      await ref.read(secureStorageProvider).setBiometricsEnabled(false);
                      ref.read(appLockProvider.notifier).refresh();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Biometric unlock disabled.')),
                      );
                    }
                  },
                ),
              ],
            ]),

            const SizedBox(height: 24),

            _sectionHeader('PRIVACY & CONTACTS'),
            _buildContainer([
              ListTile(
                leading: const Icon(Icons.block_rounded, color: AppColors.ultraviolet),
                title: const Text('Blocked Users'),
                subtitle: const Text('Manage denied and blocked contacts'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.grey500),
                onTap: () => context.push('/blocked-users'),
              ),
            ]),

            const SizedBox(height: 24),

            _sectionHeader('CHAT BACKUP (WHATSAPP-STYLE)'),
            _buildContainer([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.lavender.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.cloud_done_rounded, color: AppColors.ultraviolet, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lastBackupTime != null
                                    ? 'Last Backup: ${DateFormat('dd MMM, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_lastBackupTime!))}'
                                    : 'No backup created yet',
                                style: AppTypography.title.copyWith(fontSize: 15),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _lastBackupSize != null
                                    ? 'Size: ${(_lastBackupSize! / 1024).toStringAsFixed(1)} KB • Saved in Secure Vault (Android/media)'
                                    : 'Back up your messages and media to phone storage so you never lose them upon reinstalling.',
                                style: AppTypography.caption.copyWith(color: AppColors.grey500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isBackingUp ? null : _runImmediateBackup,
                        icon: _isBackingUp
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.backup_rounded, size: 18),
                        label: Text(_isBackingUp ? 'Backing Up...' : 'Back Up Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ultraviolet,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Auto-Backup (Daily)'),
                subtitle: const Text('Automatically backs up chats every 24h'),
                value: _isAutoBackup,
                activeThumbColor: AppColors.ultraviolet,
                onChanged: (val) async {
                  setState(() => _isAutoBackup = val);
                  await ref.read(secureStorageProvider).setAutoBackupEnabled(val);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.drive_folder_upload_rounded, color: AppColors.ultraviolet),
                title: const Text('Export to Custom Location...'),
                subtitle: const Text('Save encrypted backup to Google Drive or Downloads'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.grey500),
                onTap: _exportBackup,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_rounded, color: AppColors.ultraviolet),
                title: const Text('12-Word Recovery Phrase'),
                subtitle: const Text('View master secret phrase to restore on new devices'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.grey500),
                onTap: _viewRecoveryPhrase,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore_rounded, color: AppColors.ultraviolet),
                title: const Text('Restore / Smart Auto-Check'),
                subtitle: const Text('Scan local storage or restore from words/file'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.grey500),
                onTap: () => context.push('/restore-account'),
              ),
            ]),

            const SizedBox(height: 24),

            _sectionHeader('EMERGENCY & STORAGE'),

            _buildContainer([
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                title: const Text('Wipe All Local Data', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                subtitle: const Text('Destroy database vault and cryptographic keys'),
                onTap: _confirmEmergencyWipe,
              ),
            ]),

            const SizedBox(height: 24),

            _sectionHeader('NETWORK & RELAY'),
            _buildContainer([
              const ListTile(
                leading: Icon(Icons.cloud_outlined, color: AppColors.ultraviolet),
                title: Text('Relay Connection'),
                subtitle: Text('Local Zero-Knowledge Blinded Relay (Active)'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.security_rounded, color: AppColors.success),
                title: const Text('Firebase Status'),
                subtitle: const Text('Architecture configured (google-services.json plug-and-play)'),
                trailing: const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.grey500),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Firebase Connection Info'),
                      content: const Text(
                        'Bharosa uses a zero-knowledge blinded postbox architecture.\n\n'
                        '• Currently running on the high-speed local encrypted relay.\n'
                        '• Firebase Firestore rules, Storage rules, and Cloud Functions are fully built in your repository.\n'
                        '• To route multi-device traffic through live Firebase, place your Firebase project\'s google-services.json inside android/app/.',
                        style: TextStyle(fontSize: 14),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]),

            const SizedBox(height: 24),

            _sectionHeader('ABOUT'),
            _buildContainer([
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/images/app_logo.png', width: 40, height: 40, fit: BoxFit.cover),
                ),
                title: const Text('Bharosa Messenger'),
                subtitle: const Text('v1.0.0 (Encrypted & Secure)'),
              ),
              const Divider(),
              const ListTile(
                title: Text('Privacy Model'),
                subtitle: Text('SimpleX-inspired capability queues with instant packet deletion'),
              ),
            ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  Widget _buildContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(children: children),
    );
  }
}
