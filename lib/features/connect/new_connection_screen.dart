import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/invite.dart';

class NewConnectionScreen extends ConsumerStatefulWidget {
  const NewConnectionScreen({super.key});

  @override
  ConsumerState<NewConnectionScreen> createState() => _NewConnectionScreenState();
}

class _NewConnectionScreenState extends ConsumerState<NewConnectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pasteController = TextEditingController();

  ConnectionInvite? _generatedInvite;
  bool _isLoadingInvite = false;
  bool _isConnecting = false;
  bool _isReusable = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateInvite();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _generateInvite() async {
    setState(() => _isLoadingInvite = true);
    try {
      final connRepo = ref.read(connectionRepositoryProvider);
      final invite = await connRepo.createInvite(isReusable: _isReusable);
      if (mounted) {
        setState(() {
          _generatedInvite = invite;
          _isLoadingInvite = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingInvite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate invite: $e')),
        );
      }
    }
  }

  Future<void> _connectWithPastedInvite() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a connection link or invite code')),
      );
      return;
    }

    final invite = ConnectionInvite.fromDeepLink(text);
    if (invite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Bharosa invite format')),
      );
      return;
    }

    setState(() => _isConnecting = true);
    try {
      final connRepo = ref.read(connectionRepositoryProvider);
      final contact = await connRepo.connectWithInvite(invite);

      // Refresh conversations list
      ref.read(conversationsProvider.notifier).loadConversations();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Connected with ${contact.displayName}!'),
        ),
      );
      context.go('/chat/${contact.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('New Connection'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.ultraviolet,
          unselectedLabelColor: AppColors.grey500,
          indicatorColor: AppColors.ultraviolet,
          indicatorWeight: 3,
          labelStyle: AppTypography.button.copyWith(fontSize: 15),
          tabs: const [
            Tab(text: 'My Invite (QR)'),
            Tab(text: 'Scan / Paste'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Create Invite
          _buildCreateInviteTab(),

          // Tab 2: Scan / Paste Link
          _buildScanPasteTab(),
        ],
      ),
    );
  }

  Widget _buildCreateInviteTab() {
    if (_isLoadingInvite) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.ultraviolet),
      );
    }

    final deepLink = _generatedInvite?.toDeepLink() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          // High-Res QR Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: AppColors.softCardShadow,
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: [
                if (deepLink.isNotEmpty)
                  QrImageView(
                    data: deepLink,
                    version: QrVersions.auto,
                    size: 220.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.ink,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  _isReusable ? 'Reusable Contact Address' : 'One-Time Connection Invite',
                  style: AppTypography.title.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _isReusable
                      ? 'Anyone with this link can request connection (manual accept).'
                      : 'Automatically expires once connected or after 7 days.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Reusable Address Switch (Section 13 Decision 4)
          SwitchListTile(
            title: const Text('Reusable Contact Address'),
            subtitle: const Text('Make this invite link reusable for social bios'),
            value: _isReusable,
            activeThumbColor: AppColors.ultraviolet,
            onChanged: (val) {
              setState(() => _isReusable = val);
              _generateInvite();
            },
          ),

          const SizedBox(height: 16),

          // Action Buttons: Copy Link & Regenerate
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: deepLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite link copied to clipboard!')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy Link'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _generateInvite,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('New Key'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanPasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter Invite Link', style: AppTypography.title.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Paste the connection link or QR text shared by your contact to establish bilateral pairwise queues.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _pasteController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Paste bharosa://connect?data=... here',
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_rounded, color: AppColors.ultraviolet),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    setState(() => _pasteController.text = data!.text!);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isConnecting ? null : _connectWithPastedInvite,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: Text(_isConnecting ? 'Handshaking...' : 'Connect Now'),
            ),
          ),

          const SizedBox(height: 36),

          // Simulated QR Scanner card
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.grey200),
                boxShadow: AppColors.softCardShadow,
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 48, color: AppColors.ultraviolet),
                  const SizedBox(height: 12),
                  Text('Camera QR Scanner', style: AppTypography.title.copyWith(fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'Point camera at your friend’s device screen to instantly connect.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
