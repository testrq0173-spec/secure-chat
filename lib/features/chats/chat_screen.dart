import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/chat_bubble.dart';
import '../../core/widgets/chat_composer.dart';
import '../../data/models/conversation.dart';
import '../../data/models/message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  Conversation? _conversation;
  Message? _replyingMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final db = ref.read(databaseServiceProvider);
    final conv = await db.getConversation(widget.conversationId);
    if (mounted) {
      setState(() {
        _conversation = conv;
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _sendMessage(String text) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final reply = _replyingMessage;
    setState(() => _replyingMessage = null);

    try {
      await chatRepo.sendMessage(
        conversationId: widget.conversationId,
        content: text,
        replyToId: reply?.id,
        replyToText: reply?.content,
        replyToSender: reply?.senderName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delivery issue: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
    ref.read(conversationsProvider.notifier).loadConversations();
    _scrollToBottom();
  }

  Future<void> _sendMedia(MessageType type, String fileName, int fileSize) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    await chatRepo.sendMessage(
      conversationId: widget.conversationId,
      content: '',
      type: type,
      fileName: fileName,
      fileSize: fileSize,
    );
    ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
    ref.read(conversationsProvider.notifier).loadConversations();
    _scrollToBottom();
  }

  void _showMessageActions(Message message, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bottomSheet)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick Emoji Reaction Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['❤️', '👍', '😂', '😮', '😢', '🙏'].map((emoji) {
                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          ref.read(chatRepositoryProvider).sendReaction(
                                messageId: message.id,
                                conversationId: widget.conversationId,
                                emoji: emoji,
                              );
                          ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                        },
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: AppColors.ink),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyingMessage = message);
                  },
                ),
                if (message.content.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: AppColors.ink),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied')),
                      );
                    },
                  ),
                if (isMe && message.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: AppColors.ink),
                    title: const Text('Edit Message'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(message);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  title: const Text('Delete for Me', style: TextStyle(color: AppColors.error)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(chatRepositoryProvider).deleteForMe(message.id);
                    ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                  },
                ),
                if (isMe)
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                    title: const Text('Delete for Everyone', style: TextStyle(color: AppColors.error)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref.read(chatRepositoryProvider).deleteForEveryone(
                            messageId: message.id,
                            conversationId: widget.conversationId,
                          );
                      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDialog(Message message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Edit your message...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newText = editController.text.trim();
                if (newText.isNotEmpty && newText != message.content) {
                  await ref.read(chatRepositoryProvider).editMessage(
                        messageId: message.id,
                        newContent: newText,
                      );
                  ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDisappearingDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Disappearing Messages'),
          children: [
            _disappearingOption('Off', 0),
            _disappearingOption('1 Hour', 3600),
            _disappearingOption('24 Hours', 86400),
            _disappearingOption('7 Days', 604800),
          ],
        );
      },
    );
  }

  Widget _disappearingOption(String label, int seconds) {
    return SimpleDialogOption(
      onPressed: () async {
        Navigator.pop(context);
        final db = ref.read(databaseServiceProvider);
        final contact = await db.getContact(widget.conversationId);
        if (contact != null) {
          await db.saveContact(contact.copyWith(disappearingDurationSeconds: seconds));
        }
        final conv = await db.getConversation(widget.conversationId);
        if (conv != null) {
          await db.saveConversation(conv.copyWith(disappearingDurationSeconds: seconds));
        }
        await _loadConversation();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label, style: AppTypography.bodyMedium),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.conversationId));

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator(color: AppColors.ultraviolet)),
      );
    }

    final title = _conversation?.title ?? 'Chat';
    final isVerified = _conversation?.isVerified ?? false;
    final disappearingSeconds = _conversation?.disappearingDurationSeconds ?? 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => _handleBack(context),
          ),
          title: Row(
            children: [
              AppAvatar(
                name: title,
                radius: 18,
                isVerified: isVerified,
                isGroup: _conversation?.type == ConversationType.group,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.title.copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isVerified ? 'Verified E2EE' : 'End-to-End Encrypted',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: isVerified ? AppColors.success : AppColors.grey500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Encrypted Audio Call',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('E2EE WebRTC Calls scheduled in Phase 3')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Encrypted Video Call',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('E2EE Video Calls scheduled in Phase 3')),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'verify') {
                context.push('/security-code/${widget.conversationId}');
              } else if (val == 'disappearing') {
                _showDisappearingDialog();
              } else if (val == 'group_info') {
                context.push('/group-info/${widget.conversationId}');
              }
            },
            itemBuilder: (ctx) => [
              if (_conversation?.type == ConversationType.direct)
                const PopupMenuItem(
                  value: 'verify',
                  child: Text('Verify Security Code'),
                ),
              if (_conversation?.type == ConversationType.group)
                const PopupMenuItem(
                  value: 'group_info',
                  child: Text('Group Info'),
                ),
              const PopupMenuItem(
                value: 'disappearing',
                child: Text('Disappearing Messages'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Disappearing Messages Banner
          if (disappearingSeconds > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.warning.withValues(alpha: 0.15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Disappearing timer: ${disappearingSeconds >= 86400 ? "${disappearingSeconds ~/ 86400} days" : "${disappearingSeconds ~/ 3600} hours"}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),

          // Message Bubbles List
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.ultraviolet),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_rounded, size: 36, color: AppColors.ultraviolet),
                          const SizedBox(height: 12),
                          Text('End-to-End Encrypted', style: AppTypography.title.copyWith(fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(
                            'Messages and calls are secured with Double Ratchet forward secrecy. No one outside of this chat, not even the server, can read them.',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == 'self';

                    return ChatBubble(
                      message: msg,
                      isMe: isMe,
                      onLongPress: () => _showMessageActions(msg, isMe),
                      onReplyTap: () {
                        // Highlight or scroll to reply
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Composer
          ChatComposer(
            replyToSender: _replyingMessage?.senderName,
            replyToText: _replyingMessage?.content,
            onCancelReply: () => setState(() => _replyingMessage = null),
            onSendMessage: _sendMessage,
            onSendMedia: _sendMedia,
            onDraftChanged: (draft) {
              ref.read(databaseServiceProvider).updateConversationDraft(widget.conversationId, draft);
            },
          ),
        ],
      ),
    ),
  );
}
}
