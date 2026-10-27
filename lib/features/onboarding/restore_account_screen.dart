import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/crypto/mnemonic_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/profile.dart';

class RestoreAccountScreen extends ConsumerStatefulWidget {
  const RestoreAccountScreen({super.key});

  @override
  ConsumerState<RestoreAccountScreen> createState() => _RestoreAccountScreenState();
}

class _RestoreAccountScreenState extends ConsumerState<RestoreAccountScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Smart Discovery State
  bool _isScanning = true;
  List<BackupFileInfo> _foundBackups = [];
  String? _scanMessage;

  // 12-Word Phrase State
  final TextEditingController _phraseController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _isPhraseValid = false;
  List<String> _suggestedWords = [];
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _phraseController.addListener(_onPhraseChanged);
    _runSmartDiscovery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phraseController.removeListener(_onPhraseChanged);
    _phraseController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  /// Intelligent Discovery Algorithm:
  /// Automatically checks local storage, Downloads, Bharosa_Backups folders
  Future<void> _runSmartDiscovery() async {
    setState(() {
      _isScanning = true;
      _scanMessage = 'Scanning device storage for Bharosa backups...';
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final backups = await backupService.scanForLocalBackups();

      if (!mounted) return;
      setState(() {
        _foundBackups = backups;
        _isScanning = false;
        if (backups.isEmpty) {
          _scanMessage = 'No existing backup files found in standard folders.';
        } else {
          _scanMessage = 'Found ${backups.length} local encrypted backup(s).';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanMessage = 'Error scanning storage: $e';
      });
    }
  }

  void _onPhraseChanged() {
    final text = _phraseController.text;
    final words = text.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Check last word for suggestions
    if (words.isNotEmpty && !text.endsWith(' ')) {
      final lastWord = words.last;
      final suggestions = MnemonicService.suggestWords(lastWord);
      setState(() {
        _suggestedWords = suggestions.take(4).toList();
      });
    } else {
      if (_suggestedWords.isNotEmpty) {
        setState(() => _suggestedWords = []);
      }
    }

    final isValid = words.length == 12 && MnemonicService.validateMnemonic(text);
    if (_isPhraseValid != isValid) {
      setState(() => _isPhraseValid = isValid);
    }
  }

  void _applySuggestion(String word) {
    final text = _phraseController.text;
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      words[words.length - 1] = word;
      final newText = '${words.join(' ')} ';
      _phraseController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _phraseController.text = data!.text!.trim();
    }
  }

  // Restore via 12-Word Mnemonic Phrase
  Future<void> _restoreFromPhrase() async {
    if (!_isPhraseValid) return;

    setState(() => _isRestoring = true);
    try {
      final cleanPhrase = _phraseController.text.trim();
      final backupService = ref.read(backupServiceProvider);
      final authRepo = ref.read(authRepositoryProvider);

      bool chatsRestored = false;
      Profile? profile;

      // Smart Check: If local auto-backup exists on device, decrypt and restore chats
      final localBackups = await backupService.scanForLocalBackups();
      for (final b in localBackups) {
        try {
          profile = await backupService.restoreEncryptedBackup(
            backupFile: File(b.path),
            passphrase: cleanPhrase,
          );
          chatsRestored = true;
          break;
        } catch (_) {}
      }

      // If no local backup file was decrypted, restore cryptographic keys directly
      profile ??= await authRepo.restoreFromMnemonic(
        mnemonic: cleanPhrase,
        displayName: _displayNameController.text.trim().isNotEmpty
            ? _displayNameController.text.trim()
            : null,
      );

      // Create or load saved notes
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.getOrCreateSavedNotes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chatsRestored
                ? 'Identity & all chats restored from backup! Welcome back, ${profile.displayName}.'
                : 'Identity restored successfully! Welcome back, ${profile.displayName}.',
          ),
          backgroundColor: AppColors.success,
        ),
      );

      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore account: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  // Restore via Selected Backup File
  Future<void> _promptRestoreBackupFile(BackupFileInfo info) async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: const Text('Restore Encrypted Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File: ${info.fileName}',
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Created: ${info.formattedDate} (${info.formattedSize})',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 16),
              const Text('Enter backup passphrase to decrypt:'),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'Passphrase or 12-word phrase',
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decrypt & Restore'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && passwordCtrl.text.isNotEmpty) {
      await _executeRestoreFile(File(info.path), passwordCtrl.text.trim());
    }
  }

  Future<void> _pickAndRestoreManualFile() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (pickedFiles.isNotEmpty && pickedFiles.first.path != null) {
        final picked = pickedFiles.first;
        final file = File(picked.path!);
        final stat = await file.stat();
        final info = BackupFileInfo(
          path: file.path,
          fileName: picked.name,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        );
        if (!mounted) return;
        await _promptRestoreBackupFile(info);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select file: $e')),
      );
    }
  }

  Future<void> _executeRestoreFile(File file, String passphrase) async {
    setState(() => _isRestoring = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      final profile = await backupService.restoreEncryptedBackup(
        backupFile: file,
        passphrase: passphrase,
      );

      // Initialize chat repository notes
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.getOrCreateSavedNotes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup restored successfully! Welcome back, ${profile.displayName}.'),
          backgroundColor: AppColors.success,
        ),
      );

      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Restore Account'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.ultraviolet,
          indicatorColor: AppColors.ultraviolet,
          tabs: const [
            Tab(
              icon: Icon(Icons.cloud_sync_rounded, size: 20),
              text: 'Smart Auto-Check',
            ),
            Tab(
              icon: Icon(Icons.vpn_key_rounded, size: 20),
              text: '12-Word Phrase',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // TAB 1: Smart Auto-Check & Backup File
            _buildSmartDiscoveryTab(),

            // TAB 2: 12-Word Secret Recovery Phrase
            _build12WordPhraseTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartDiscoveryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lavender.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.lavender),
            ),
            child: Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.ultraviolet),
                  )
                else
                  Icon(
                    _foundBackups.isNotEmpty ? Icons.verified_rounded : Icons.info_outline_rounded,
                    color: _foundBackups.isNotEmpty ? AppColors.success : AppColors.ultraviolet,
                    size: 24,
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _scanMessage ?? 'Scanning...',
                    style: AppTypography.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!_isScanning)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.ultraviolet),
                    tooltip: 'Rescan Storage',
                    onPressed: _runSmartDiscovery,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_foundBackups.isNotEmpty) ...[
            Text(
              'DISCOVERED BACKUP FILES',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _foundBackups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final backup = _foundBackups[index];
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
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.lavender.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.shield_rounded, color: AppColors.ultraviolet, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  backup.fileName,
                                  style: AppTypography.title.copyWith(fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${backup.formattedDate} • ${backup.formattedSize}',
                                  style: AppTypography.caption.copyWith(color: AppColors.grey500),
                                ),
                                if (backup.isAutoBackup) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.bolt_rounded, size: 12, color: AppColors.success),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Auto-Backup (WhatsApp style)',
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isRestoring ? null : () => _promptRestoreBackupFile(backup),
                          icon: const Icon(Icons.restore_page_rounded, size: 18),
                          label: const Text('Restore from this Backup'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          Text(
            'MANUAL FILE RESTORATION',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Have a backup file (.enc) stored elsewhere?',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a file from your Downloads, SD Card, or cloud drive to decrypt and restore all conversations.',
                  style: AppTypography.caption.copyWith(color: AppColors.grey500),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isRestoring ? null : _pickAndRestoreManualFile,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Browse Device Files'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _build12WordPhraseTab() {
    final words = _phraseController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCount = words.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secret Recovery Phrase',
            style: AppTypography.display.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your 12 secret words in exact order. Your Ed25519 cryptographic identity and public keys will be regenerated deterministically.',
            style: AppTypography.caption.copyWith(color: AppColors.grey500, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Phrase Input Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: _isPhraseValid
                    ? AppColors.success
                    : (wordCount == 12 ? AppColors.error : AppColors.grey200),
                width: _isPhraseValid || wordCount == 12 ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Words: $wordCount / 12',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: wordCount == 12
                            ? (_isPhraseValid ? AppColors.success : AppColors.error)
                            : AppColors.grey500,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_rounded, size: 16),
                      label: const Text('Paste'),
                    ),
                  ],
                ),
                TextField(
                  controller: _phraseController,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. apple banana castle dolphin eagle forest grain harvest...',
                  ),
                ),
                if (_isPhraseValid) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Valid BIP-39 Recovery Phrase',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ] else if (wordCount == 12) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Invalid checksum or misspelled word',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Word auto-suggestions
          if (_suggestedWords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _suggestedWords.map((word) {
                return ActionChip(
                  label: Text(word),
                  onPressed: () => _applySuggestion(word),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Optional Display Name
          Text(
            'Display Name (Optional)',
            style: AppTypography.title.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              hintText: 'Enter your name (optional)',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),

          const SizedBox(height: 36),

          // Restore Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isPhraseValid && !_isRestoring) ? _restoreFromPhrase : null,
              child: _isRestoring
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                    )
                  : const Text('Restore Account & Identity'),
            ),
          ),
        ],
      ),
    );
  }
}
