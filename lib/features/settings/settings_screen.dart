import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/crypto/crypto_utils.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/screen_protector_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isScreenshotBlocked = false;
  bool _isIncognito = false;
  String? _publicKeyFingerprint;

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

    if (mounted) {
      setState(() {
        _isScreenshotBlocked = screenshot;
        _isIncognito = incognito;
        _publicKeyFingerprint = fp;
      });
    }
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
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.grey200),
                    boxShadow: AppColors.softCardShadow,
                  ),
                  child: Row(
                    children: [
                      AppAvatar(name: name, radius: 30),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: AppTypography.title.copyWith(fontSize: 18)),
                            const SizedBox(height: 2),
                            Text(
                              'Key ID: ${_publicKeyFingerprint ?? "..."}',
                              style: AppTypography.caption.copyWith(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.grey500),
                        tooltip: 'Copy Fingerprint',
                        onPressed: () {
                          if (_publicKeyFingerprint != null) {
                            Clipboard.setData(ClipboardData(text: _publicKeyFingerprint!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Identity fingerprint copied!')),
                            );
                          }
                        },
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
              const ListTile(
                title: Text('Bharosa Messenger'),
                subtitle: Text('v1.0.0 (Phase 0 to Phase 2 Production Ready)'),
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
