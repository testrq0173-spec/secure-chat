import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../data/models/message.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'voice_player_widget.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final List<String> reactions;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;
  final Function(String emoji)? onReactionTap;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.reactions = const [],
    this.onLongPress,
    this.onReplyTap,
    this.onReactionTap,
  });

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('h:mm a').format(dt);
  }

  void _openFile(BuildContext context) async {
    if (message.filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File path is unavailable')),
      );
      return;
    }
    final file = File(message.filePath!);
    final exists = await file.exists();
    if (!context.mounted) return;
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on device storage')),
      );
      return;
    }
    try {
      await OpenFilex.open(message.filePath!);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  void _showFullImage(BuildContext context) {
    if (message.filePath == null) return;
    final file = File(message.filePath!);
    if (!file.existsSync()) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.file(file),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe ? AppColors.ultraviolet : AppColors.lavender;
    final textColor = isMe ? AppColors.white : AppColors.ink;
    final metaColor = isMe ? AppColors.white.withValues(alpha: 0.75) : AppColors.grey500;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Group sender name if incoming group message
                if (!isMe && message.senderName != 'Me' && !message.isSavedNote)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.senderName,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ultraviolet,
                      ),
                    ),
                  ),

                Container(
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppRadius.bubble),
                      topRight: const Radius.circular(AppRadius.bubble),
                      bottomLeft: isMe ? const Radius.circular(AppRadius.bubble) : const Radius.circular(AppRadius.bubbleTail),
                      bottomRight: isMe ? const Radius.circular(AppRadius.bubbleTail) : const Radius.circular(AppRadius.bubble),
                    ),
                    boxShadow: AppColors.softCardShadow,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reply Preview Banner
                      if (message.replyToText != null && message.replyToText!.isNotEmpty)
                        GestureDetector(
                          onTap: onReplyTap,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? AppColors.white.withValues(alpha: 0.15)
                                  : AppColors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: isMe ? AppColors.white : AppColors.ultraviolet,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.replyToSender ?? 'Reply',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isMe ? AppColors.white : AppColors.ultraviolet,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  message.replyToText!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Media Content Rendering
                      if (message.type == MessageType.image) ...[
                        GestureDetector(
                          onTap: () => _showFullImage(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: (message.filePath != null && File(message.filePath!).existsSync())
                                ? Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Image.file(
                                        File(message.filePath!),
                                        height: 180,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                      Container(
                                        margin: const EdgeInsets.all(8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${((message.fileSize ?? 0) / 1024).toStringAsFixed(0)} KB',
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                      if (message.status == MessageStatus.sending)
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.black45,
                                            child: Center(
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.65),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  )
                                : Container(
                                    height: 140,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: isMe ? AppColors.white.withValues(alpha: 0.2) : AppColors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.ultraviolet),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          message.fileName ?? 'Receiving photo...',
                                          style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ] else if (message.type == MessageType.video) ...[
                        GestureDetector(
                          onTap: () => _openFile(context),
                          child: Container(
                            height: 140,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.white.withValues(alpha: 0.18) : AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.play_circle_fill_rounded,
                                      size: 48,
                                      color: isMe ? AppColors.white : AppColors.ultraviolet,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      message.fileName ?? 'Encrypted Video',
                                      style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${((message.fileSize ?? 1048576) / (1024 * 1024)).toStringAsFixed(1)} MB',
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                ),
                                if (message.status == MessageStatus.sending)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.65),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (message.filePath == null || !File(message.filePath!).existsSync())
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isMe ? AppColors.white.withValues(alpha: 0.18) : AppColors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.ultraviolet),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            message.fileName ?? 'Receiving video...',
                                            style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ] else if (message.type == MessageType.file) ...[
                        GestureDetector(
                          onTap: () => _openFile(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.white.withValues(alpha: 0.15) : AppColors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isMe ? AppColors.white : AppColors.ultraviolet).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.insert_drive_file_rounded,
                                    color: isMe ? AppColors.white : AppColors.ultraviolet,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.fileName ?? 'Encrypted Document',
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${((message.fileSize ?? 102400) / 1024).toStringAsFixed(1)} KB',
                                        style: TextStyle(color: metaColor, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_circle_down_rounded, size: 20, color: metaColor),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ] else if (message.type == MessageType.voice) ...[
                        VoicePlayerWidget(
                          filePath: message.filePath,
                          durationMs: message.mediaDurationMs,
                          isMe: isMe,
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Message Text
                      if (message.content.isNotEmpty)
                        Text(
                          message.content,
                          style: AppTypography.body.copyWith(
                            color: textColor,
                            fontSize: 15,
                          ),
                        ),

                      const SizedBox(height: 4),

                      // Metadata Row: Time, Edited status, Disappearing clock, Delivery ticks
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isEdited)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                'edited',
                                style: TextStyle(
                                  color: metaColor,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (message.expiresAt != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: metaColor,
                              ),
                            ),
                          Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(
                              color: metaColor,
                              fontSize: 11,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            if (message.status == MessageStatus.sending)
                              Icon(Icons.access_time_rounded, size: 13, color: metaColor)
                            else if (message.status == MessageStatus.sent)
                              Icon(Icons.check_rounded, size: 13, color: metaColor)
                            else if (message.status == MessageStatus.delivered)
                              const Icon(Icons.done_all_rounded, size: 14, color: AppColors.white)
                            else if (message.status == MessageStatus.failed)
                              const Icon(Icons.error_outline_rounded, size: 13, color: AppColors.error),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Reaction Emojis Display
                if (reactions.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(0, -6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.grey200),
                        boxShadow: AppColors.softCardShadow,
                      ),
                      child: Text(
                        reactions.join(' '),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
