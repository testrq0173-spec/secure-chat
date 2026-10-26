import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/colors.dart';
import '../../core/widgets/app_avatar.dart';

/// WhatsApp-style Fullscreen Image Viewer with Interactive Pinch-to-Zoom,
/// auto-fading Top/Bottom Overlays, Star bookmarking, and fully working Action Menu.
class ImageViewerScreen extends StatefulWidget {
  final String filePath;
  final String senderName;
  final int timestamp;
  final String? caption;
  final String? messageId;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;

  const ImageViewerScreen({
    super.key,
    required this.filePath,
    required this.senderName,
    required this.timestamp,
    this.caption,
    this.messageId,
    this.onReply,
    this.onDelete,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> with SingleTickerProviderStateMixin {
  bool _showOverlays = true;
  bool _isStarred = false;
  late final TransformationController _transformController;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  String _formatDateTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today, ${DateFormat('h:mm a').format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day && dt.month == yesterday.month && dt.year == yesterday.year) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      final matrix = Matrix4.identity();
      matrix.setEntry(0, 0, 2.5);
      matrix.setEntry(1, 1, 2.5);
      matrix.setEntry(0, 3, -position.dx * 1.5);
      matrix.setEntry(1, 3, -position.dy * 1.5);
      _transformController.value = matrix;
    }
  }

  Future<void> _saveToDownloads() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) throw 'File does not exist on disk';

      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        }
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final fileName = 'Bharosa_${DateTime.now().millisecondsSinceEpoch}${p.extension(widget.filePath)}';
      final savedFile = File('${targetDir.path}/$fileName');
      await file.copy(savedFile.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads: $fileName'),
            backgroundColor: AppColors.ink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _shareFile() async {
    try {
      await OpenFilex.open(widget.filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    final fileExists = file.existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Center Image Space (Interactive Pinch-to-Zoom & Double-Tap)
          GestureDetector(
            onTap: () => setState(() => _showOverlays = !_showOverlays),
            onDoubleTapDown: (d) => _doubleTapDetails = d,
            onDoubleTap: _handleDoubleTap,
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
                // Swipe up to reply
                if (widget.onReply != null) {
                  Navigator.pop(context);
                  widget.onReply!();
                }
              }
            },
            child: Container(
              color: Colors.black,
              child: Center(
                child: fileExists
                    ? InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 0.8,
                        maxScale: 5.0,
                        clipBehavior: Clip.none,
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 56),
                          SizedBox(height: 12),
                          Text('Image not found on device', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
              ),
            ),
          ),

          // Top Overlay (Fades out / in)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _showOverlays ? 1.0 : 0.0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black87,
                      Colors.black45,
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                          onPressed: () => Navigator.pop(context),
                        ),
                        AppAvatar(
                          name: widget.senderName,
                          radius: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.senderName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(widget.timestamp),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                            color: _isStarred ? Colors.amber : Colors.white,
                            size: 24,
                          ),
                          tooltip: 'Star',
                          onPressed: () {
                            setState(() => _isStarred = !_isStarred);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_isStarred ? 'Message starred' : 'Message unstarred'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                          color: const Color(0xFF242232),
                          onSelected: (val) async {
                            if (val == 'share') {
                              await _shareFile();
                            } else if (val == 'save') {
                              await _saveToDownloads();
                            } else if (val == 'copy') {
                              Clipboard.setData(ClipboardData(text: widget.filePath));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('File path copied to clipboard')),
                                );
                              }
                            } else if (val == 'delete') {
                              if (widget.onDelete != null) {
                                widget.onDelete!();
                                Navigator.pop(context);
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_outlined, color: Colors.white, size: 20),
                                  SizedBox(width: 12),
                                  Text('Share', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'save',
                              child: Row(
                                children: [
                                  Icon(Icons.download_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 12),
                                  Text('Save to Downloads', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(Icons.copy_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 12),
                                  Text('Copy Path', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                  SizedBox(width: 12),
                                  Text('Delete', style: TextStyle(color: AppColors.error)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Overlay (Caption & Reply Action)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _showOverlays ? 1.0 : 0.0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black87,
                      Colors.black54,
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Caption attached to image
                        if (widget.caption != null && widget.caption!.trim().isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.caption!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Reply Bar
                        GestureDetector(
                          onTap: () {
                            if (widget.onReply != null) {
                              Navigator.pop(context);
                              widget.onReply!();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.reply_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Swipe up to reply',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
