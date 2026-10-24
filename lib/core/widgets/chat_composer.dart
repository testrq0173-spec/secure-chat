import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../data/models/message.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

typedef SendMediaCallback = void Function({
  required MessageType type,
  required String filePath,
  required String fileName,
  required int fileSize,
  int? mediaDurationMs,
});

class ChatComposer extends StatefulWidget {
  final String? initialText;
  final String? replyToSender;
  final String? replyToText;
  final VoidCallback? onCancelReply;
  final Function(String text) onSendMessage;
  final SendMediaCallback onSendMedia;
  final Function(String text)? onDraftChanged;

  const ChatComposer({
    super.key,
    this.initialText,
    this.replyToSender,
    this.replyToText,
    this.onCancelReply,
    required this.onSendMessage,
    required this.onSendMedia,
    this.onDraftChanged,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final TextEditingController _controller;
  bool _hasText = false;
  bool _isRecordingVoice = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  AudioRecorder? _audioRecorder;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _hasText = _controller.text.trim().isNotEmpty;
    _audioRecorder = AudioRecorder();

    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
      widget.onDraftChanged?.call(_controller.text);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _controller.dispose();
    _audioRecorder?.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _controller.clear();
  }

  Future<void> _startRecording() async {
    final recorder = _audioRecorder;
    if (recorder == null) return;

    final hasPerm = await recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record voice notes')),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecordingVoice = true;
        _recordDurationSeconds = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordDurationSeconds++;
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start voice recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording({required bool shouldSend}) async {
    _recordTimer?.cancel();
    _recordTimer = null;

    final recorder = _audioRecorder;
    if (recorder == null) return;

    try {
      final path = await recorder.stop();
      final duration = _recordDurationSeconds;

      setState(() {
        _isRecordingVoice = false;
        _recordDurationSeconds = 0;
      });

      if (!shouldSend || path == null) {
        // Discard recording
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        return;
      }

      final file = File(path);
      if (await file.exists()) {
        final fileSize = await file.length();
        widget.onSendMedia(
          type: MessageType.voice,
          filePath: path,
          fileName: 'Voice_Note_${DateTime.now().millisecondsSinceEpoch}.m4a',
          fileSize: fileSize,
          mediaDurationMs: duration * 1000,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      final size = await file.length();
      final fileName = xfile.name.isNotEmpty ? xfile.name : 'Photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

      widget.onSendMedia(
        type: MessageType.image,
        filePath: xfile.path,
        fileName: fileName,
        fileSize: size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select photo: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final xvideo = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 45),
      );
      if (xvideo == null) return;

      final file = File(xvideo.path);
      final size = await file.length();

      if (size > 12 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video is too large (max 12 MB). Please choose a shorter clip.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      final fileName = xvideo.name.isNotEmpty ? xvideo.name : 'Video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      widget.onSendMedia(
        type: MessageType.video,
        filePath: xvideo.path,
        fileName: fileName,
        fileSize: size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select video: $e')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (pickedFiles.isEmpty) return;

      final pickedFile = pickedFiles.first;
      if (pickedFile.path == null) return;
      final fileSize = await File(pickedFile.path!).length();

      widget.onSendMedia(
        type: MessageType.file,
        filePath: pickedFile.path!,
        fileName: pickedFile.name,
        fileSize: fileSize,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select document: $e')),
        );
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bottomSheet)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Encrypted Attachment',
                  style: AppTypography.title.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _attachmentItem(
                      icon: Icons.photo_library_rounded,
                      color: AppColors.ultraviolet,
                      label: 'Gallery',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.camera_alt_rounded,
                      color: const Color(0xFF2E7D32),
                      label: 'Camera',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.videocam_rounded,
                      color: AppColors.error,
                      label: 'Video',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickVideo(ImageSource.gallery);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.insert_drive_file_rounded,
                      color: const Color(0xFF0288D1),
                      label: 'Document',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickDocument();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _attachmentItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply Preview Bar
            if (widget.replyToText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.lavender.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.ultraviolet,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to ${widget.replyToSender ?? "Message"}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ultraviolet,
                            ),
                          ),
                          Text(
                            widget.replyToText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.grey500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.grey500),
                      onPressed: widget.onCancelReply,
                    ),
                  ],
                ),
              ),

            // Active Recording State Bar
            if (_isRecordingVoice)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // Blinking Record Dot
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recording: ${_formatTimer(_recordDurationSeconds)}',
                      style: AppTypography.title.copyWith(fontSize: 15, color: AppColors.error),
                    ),
                    const Spacer(),
                    // Cancel / Delete button
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.grey500, size: 26),
                      tooltip: 'Cancel Recording',
                      onPressed: () => _stopRecording(shouldSend: false),
                    ),
                    const SizedBox(width: 4),
                    // Send recording button
                    GestureDetector(
                      onTap: () => _stopRecording(shouldSend: true),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: AppColors.ultraviolet,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: AppColors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              )
            else
              // Standard Input Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.ultraviolet, size: 28),
                      tooltip: 'Add Attachment',
                      onPressed: _showAttachmentMenu,
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.grey200),
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Encrypted message...',
                            hintStyle: AppTypography.caption.copyWith(fontSize: 15),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_hasText)
                      GestureDetector(
                        onTap: _send,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.ultraviolet,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_upward_rounded, color: AppColors.white, size: 24),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _startRecording,
                        onLongPress: _startRecording,
                        onLongPressEnd: (_) => _stopRecording(shouldSend: true),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.grey200),
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: AppColors.ultraviolet,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
