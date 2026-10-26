import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/app_avatar.dart';

/// WhatsApp-style Fullscreen Video Player with scrub timeline, info sheet,
/// auto-fading controls, center play/pause overlay, and bottom reply composer.
class VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final String senderName;
  final int timestamp;
  final String? caption;
  final String? fileName;
  final int? fileSize;
  final Function(String replyText)? onSendReply;
  final VoidCallback? onDelete;

  const VideoPlayerScreen({
    super.key,
    required this.filePath,
    required this.senderName,
    required this.timestamp,
    this.caption,
    this.fileName,
    this.fileSize,
    this.onSendReply,
    this.onDelete,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isSeeking = false;
  double _sliderValue = 0.0;
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final file = File(widget.filePath);
    if (!await file.exists()) return;

    _controller = VideoPlayerController.file(file);
    try {
      await _controller.initialize();
      _controller.addListener(_videoListener);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      }
    } catch (e) {
      debugPrint('Video init error: $e');
    }
  }

  void _videoListener() {
    if (!mounted || _isSeeking) return;
    setState(() {
      final duration = _controller.value.duration.inMilliseconds;
      final position = _controller.value.position.inMilliseconds;
      if (duration > 0) {
        _sliderValue = (position / duration).clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    _replyController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
      } else {
        _controller.play();
      }
    });
  }

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1C2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.ultraviolet, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Media Details',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildInfoRow('Sender', widget.senderName),
              _buildInfoRow('Sent At', _formatDateTime(widget.timestamp)),
              _buildInfoRow('File Name', widget.fileName ?? p.basename(widget.filePath)),
              if (widget.fileSize != null)
                _buildInfoRow('Size', '${(widget.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'),
              if (_isInitialized)
                _buildInfoRow('Duration', _formatDuration(_controller.value.duration)),
              _buildInfoRow('Encryption', 'Double Ratchet Forward Secrecy (E2EE)'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToDownloads() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) throw 'File not found';

      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        }
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final fName = 'Bharosa_${DateTime.now().millisecondsSinceEpoch}${p.extension(widget.filePath)}';
      final savedFile = File('${targetDir.path}/$fName');
      await file.copy(savedFile.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video saved to Downloads: $fName'),
            backgroundColor: AppColors.ink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
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
          // Video Playback Area
          GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: Center(
              child: _isInitialized && fileExists
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : fileExists
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppColors.ultraviolet),
                            SizedBox(height: 16),
                            Text('Loading encrypted video...', style: TextStyle(color: Colors.white70)),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 56),
                            SizedBox(height: 12),
                            Text('Video file not found', style: TextStyle(color: Colors.white54)),
                          ],
                        ),
            ),
          ),

          // Center Play/Pause Button Overlay (Fades out during playback)
          if (_isInitialized)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: (_showControls || !_controller.value.isPlaying) ? 1.0 : 0.0,
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Icon(
                      _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

          // Top Bar (Controls / Info / Close)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showControls ? 1.0 : 0.0,
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
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        AppAvatar(name: widget.senderName, radius: 19),
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
                          icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
                          tooltip: 'Info',
                          onPressed: _showInfoSheet,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                          color: const Color(0xFF242232),
                          onSelected: (val) async {
                            if (val == 'share') {
                              await OpenFilex.open(widget.filePath);
                            } else if (val == 'save') {
                              await _saveToDownloads();
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
                                  Text('Share Video', style: TextStyle(color: Colors.white)),
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
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls (Timeline, Caption, Reply Bar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showControls ? 1.0 : 0.0,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Bar & Play/Pause Controls
                        if (_isInitialized)
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                              Text(
                                _formatDuration(_controller.value.position),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbColor: AppColors.ultraviolet,
                                    activeTrackColor: AppColors.ultraviolet,
                                    inactiveTrackColor: Colors.white30,
                                    trackHeight: 3.5,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  ),
                                  child: Slider(
                                    value: _sliderValue,
                                    onChangeStart: (_) => _isSeeking = true,
                                    onChanged: (v) {
                                      setState(() => _sliderValue = v);
                                    },
                                    onChangeEnd: (v) {
                                      _isSeeking = false;
                                      final targetMs = (_controller.value.duration.inMilliseconds * v).toInt();
                                      _controller.seekTo(Duration(milliseconds: targetMs));
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(_controller.value.duration),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),

                        // Caption Area (if available)
                        if (widget.caption != null && widget.caption!.trim().isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.caption!,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Bottom Reply Bar
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: TextField(
                                  controller: _replyController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Reply...',
                                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: const BoxDecoration(
                                color: AppColors.ultraviolet,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                onPressed: () {
                                  final text = _replyController.text.trim();
                                  if (text.isNotEmpty) {
                                    if (widget.onSendReply != null) {
                                      widget.onSendReply!(text);
                                    }
                                    Navigator.pop(context);
                                  }
                                },
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
        ],
      ),
    );
  }
}
