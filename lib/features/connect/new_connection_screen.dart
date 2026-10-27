import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/invite.dart';

class NewConnectionScreen extends ConsumerStatefulWidget {
  final String? initialInviteCode;
  const NewConnectionScreen({super.key, this.initialInviteCode});

  @override
  ConsumerState<NewConnectionScreen> createState() => _NewConnectionScreenState();
}

class _NewConnectionScreenState extends ConsumerState<NewConnectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pasteController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  ConnectionInvite? _generatedInvite;
  bool _isLoadingInvite = false;
  bool _isConnecting = false;
  bool _isReusable = false;
  bool _isScanningMode = true; // true = camera, false = manual paste
  bool _hasProcessedCode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _hasProcessedCode = false;
      }
      setState(() {});
    });
    
    if (widget.initialInviteCode != null && widget.initialInviteCode!.trim().isNotEmpty) {
      _tabController.index = 1;
      _isScanningMode = false;
      _pasteController.text = widget.initialInviteCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleScannedCode(widget.initialInviteCode!);
      });
    }

    _generateInvite();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _generateInvite() async {
    setState(() => _isLoadingInvite = true);
    try {
      final connRepo = ref.read(connectionRepositoryProvider);
      final invite = await connRepo.createInvite(isReusable: _isReusable);
      
      // Immediately start listening on this invite queue for real-time handshake delivery
      ref.read(chatRepositoryProvider).listenToInviteQueue(invite.inboxQueueId);

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

  Future<void> _handleScannedCode(String rawCode) async {
    if (_hasProcessedCode || _isConnecting) return;
    _hasProcessedCode = true;

    final trimmed = rawCode.trim();
    final invite = ConnectionInvite.fromDeepLink(trimmed);
    if (invite == null) {
      _hasProcessedCode = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code format')),
        );
      }
      return;
    }

    // 1. Duplicate check: Has this user already been added?
    final db = ref.read(databaseServiceProvider);
    final existing = await db.getContactByPeerKey(invite.inviterIdentityKey) ??
                     await db.getContactBySendQueue(invite.inboxQueueId);

    if (existing != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User is already added'),
          backgroundColor: AppColors.ultraviolet,
          duration: Duration(seconds: 2),
        ),
      );
      context.push('/chat/${existing.id}');
      return;
    }

    // 2. Connect as new contact
    setState(() => _isConnecting = true);
    try {
      final connRepo = ref.read(connectionRepositoryProvider);
      final contact = await connRepo.connectWithInvite(invite);

      // Start listening to the peer's queue immediately
      ref.read(chatRepositoryProvider).ensureListening(contact.id);
      ref.read(conversationsProvider.notifier).loadConversations();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Connected with ${contact.displayName}! Send a message.'),
        ),
      );
      context.push('/chat/${contact.id}');
    } catch (e) {
      _hasProcessedCode = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final barcodeCapture = await _scannerController.analyzeImage(picked.path);
      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        final code = barcodeCapture.barcodes.first.rawValue;
        if (code != null) {
          await _handleScannedCode(code);
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR code detected in the selected image.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing gallery image: $e')),
        );
      }
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
            Tab(text: 'Scan & Connect'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyInviteTab(),
          _buildScanConnectTab(),
        ],
      ),
    );
  }

  Widget _buildMyInviteTab() {
    if (_isLoadingInvite) {
      return const Center(child: CircularProgressIndicator(color: AppColors.ultraviolet));
    }

    if (_generatedInvite == null) {
      return Center(
        child: ElevatedButton(
          onPressed: _generateInvite,
          child: const Text('Generate Invite QR'),
        ),
      );
    }

    final deepLink = _generatedInvite!.toDeepLink();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Text('Pairwise Ephemeral Handshake', style: AppTypography.title.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            'Ask your friend to scan this QR code or share the invite link below. As soon as they connect, you will receive a notification.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          const SizedBox(height: 20),

          // QR Code Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: AppColors.softCardShadow,
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: [
                QrImageView(
                  data: deepLink,
                  version: QrVersions.auto,
                  size: 220.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.ultraviolet,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isReusable ? 'Reusable Contact Address' : 'Single-Use Ephemeral Postbox',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isReusable ? AppColors.success : AppColors.ultraviolet,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Reusable Switch
          SwitchListTile(
            title: const Text('Reusable Invite Address'),
            subtitle: const Text('Allow multiple friends to connect using this same address'),
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

  Widget _buildScanConnectTab() {
    return Column(
      children: [
        // Mode Switcher: Camera QR vs Manual Paste
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Camera QR Scan'),
                    ],
                  ),
                  selected: _isScanningMode,
                  selectedColor: AppColors.ultraviolet,
                  labelStyle: TextStyle(
                    color: _isScanningMode ? AppColors.white : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) => setState(() => _isScanningMode = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.paste_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Paste Link'),
                    ],
                  ),
                  selected: !_isScanningMode,
                  selectedColor: AppColors.ultraviolet,
                  labelStyle: TextStyle(
                    color: !_isScanningMode ? AppColors.white : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) => setState(() => _isScanningMode = false),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isScanningMode ? _buildCameraScannerView() : _buildManualPasteView(),
        ),
      ],
    );
  }

  Widget _buildCameraScannerView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  final barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      _handleScannedCode(barcode.rawValue!);
                      break;
                    }
                  }
                },
              ),

              // Viewfinder Overlay
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.ultraviolet, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),

              if (_isConnecting)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.white),
                        SizedBox(height: 16),
                        Text(
                          'Connecting pairwise key...',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              // Camera Control Overlay
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                      onPressed: () => _scannerController.toggleTorch(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                      onPressed: () => _scannerController.switchCamera(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Gallery Upload Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: AppColors.white,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lavender,
                foregroundColor: AppColors.ultraviolet,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _pickImageFromGallery,
              icon: const Icon(Icons.photo_library_rounded, size: 20),
              label: const Text(
                'Upload QR from Gallery',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualPasteView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
              onPressed: _isConnecting ? null : () => _handleScannedCode(_pasteController.text),
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

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickImageFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pick QR from Gallery'),
            ),
          ),
        ],
      ),
    );
  }
}
