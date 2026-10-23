import 'package:flutter/material.dart';
import '../../data/models/message.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class ChatComposer extends StatefulWidget {
  final String? initialText;
  final String? replyToSender;
  final String? replyToText;
  final VoidCallback? onCancelReply;
  final Function(String text) onSendMessage;
  final Function(MessageType type, String fileName, int fileSize) onSendMedia;
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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _hasText = _controller.text.trim().isNotEmpty;
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
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _controller.clear();
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _attachmentItem(
                      icon: Icons.image_rounded,
                      color: AppColors.ultraviolet,
                      label: 'Photo',
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onSendMedia(MessageType.image, 'Photo_${DateTime.now().millisecondsSinceEpoch}.jpg', 512000);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.insert_drive_file_rounded,
                      color: AppColors.success,
                      label: 'Document',
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onSendMedia(MessageType.file, 'Encrypted_Doc.pdf', 1048576);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.mic_rounded,
                      color: AppColors.warning,
                      label: 'Voice Note',
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onSendMedia(MessageType.voice, 'Voice_Note.aac', 256000);
                      },
                    ),
                    _attachmentItem(
                      icon: Icons.videocam_rounded,
                      color: AppColors.error,
                      label: 'Video',
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onSendMedia(MessageType.video, 'Secure_Video.mp4', 4194304);
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
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: const Border(top: BorderSide(color: AppColors.grey200)),
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

            // Input Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.ultraviolet, size: 28),
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
                      onLongPress: () {
                        setState(() => _isRecordingVoice = true);
                      },
                      onLongPressEnd: (_) {
                        setState(() => _isRecordingVoice = false);
                        widget.onSendMedia(MessageType.voice, 'Voice_${DateTime.now().millisecondsSinceEpoch}.aac', 300000);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isRecordingVoice ? AppColors.error : AppColors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.grey200),
                        ),
                        child: Icon(
                          Icons.mic_rounded,
                          color: _isRecordingVoice ? AppColors.white : AppColors.ink,
                          size: 22,
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
