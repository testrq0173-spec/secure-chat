import 'dart:async';
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
import '../../core/widgets/swipe_to_reply.dart';
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
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _loadConversation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRepositoryProvider).ensureListening(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
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

  String _getMessageReplyPreview(Message message) {
    if (message.content.trim().isNotEmpty) {
      if (message.type == MessageType.image) return '📷 ${message.content.trim()}';
      if (message.type == MessageType.video) return '🎥 ${message.content.trim()}';
      return message.content.trim();
    }
    switch (message.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        return '🎤 Voice note';
      case MessageType.file:
        return '📄 ${message.fileName ?? "Document"}';
      case MessageType.text:
        return 'Message';
    }
  }

  void _scrollToAndHighlight(String targetMessageId, List<Message> messages) {
    final targetIndex = messages.indexWhere((m) => m.id == targetMessageId);
    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message not found in this chat')),
      );
      return;
    }

    setState(() {
      _highlightedMessageId = targetMessageId;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });

    final targetKey = _messageKeys[targetMessageId];
    if (targetKey?.currentContext != null) {
      Scrollable.ensureVisible(
        targetKey!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        alignment: 0.5,
      );
    } else if (_scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = (targetIndex / messages.length) * maxExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _messageKeys[targetMessageId]?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: 0.5,
            );
          }
        });
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final reply = _replyingMessage;
    setState(() => _replyingMessage = null);

    final replyText = reply != null ? _getMessageReplyPreview(reply) : null;
    final replySender = reply != null ? (reply.senderId == 'self' ? 'You' : reply.senderName) : null;

    try {
      await chatRepo.sendMessage(
        conversationId: widget.conversationId,
        content: text,
        replyToId: reply?.id,
        replyToText: replyText,
        replyToSender: replySender,
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

  Future<void> _sendMedia({
    required MessageType type,
    required String filePath,
    required String fileName,
    required int fileSize,
    int? mediaDurationMs,
  }) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final reply = _replyingMessage;
    setState(() => _replyingMessage = null);

    final replyText = reply != null ? _getMessageReplyPreview(reply) : null;
    final replySender = reply != null ? (reply.senderId == 'self' ? 'You' : reply.senderName) : null;

    chatRepo.sendMessage(
      conversationId: widget.conversationId,
      content: '',
      type: type,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mediaDurationMs: mediaDurationMs,
      replyToId: reply?.id,
      replyToText: replyText,
      replyToSender: replySender,
    ).then((_) {
      if (mounted) {
        ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
        ref.read(conversationsProvider.notifier).loadConversations();
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Media delivery error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
      }
    });

    // Immediately reload messages to show thumbnail with loading spinner on top!
    await Future.delayed(const Duration(milliseconds: 60));
    if (mounted) {
      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
      ref.read(conversationsProvider.notifier).loadConversations();
      _scrollToBottom();
    }
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
    ref.listen(chatMessagesProvider(widget.conversationId), (previous, next) {
      _scrollToBottom();
    });

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

          // Message Bubbles List with Pull-to-Refresh
          Expanded(
            child: RefreshIndicator(
              color: AppColors.ultraviolet,
              backgroundColor: AppColors.white,
              onRefresh: () async {
                await ref.read(chatRepositoryProvider).ensureListening(widget.conversationId);
                await ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                await _loadConversation();
              },
              child: messagesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.ultraviolet),
                ),
                error: (err, _) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: 400,
                    child: Center(child: Text('Error: $err')),
                  ),
                ),
                data: (messages) {
                  if (messages.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
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
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderId == 'self';

                      return SwipeToReply(
                        isMe: isMe,
                        onReply: () {
                          setState(() => _replyingMessage = msg);
                        },
                        child: ChatBubble(
                          key: _messageKeys.putIfAbsent(msg.id, () => GlobalKey()),
                          message: msg,
                          isMe: isMe,
                          isHighlighted: _highlightedMessageId == msg.id,
                          onLongPress: () => _showMessageActions(msg, isMe),
                          onSwipeReply: () {
                            setState(() => _replyingMessage = msg);
                          },
                          onReplyTap: () {
                            if (msg.replyToId != null) {
                              _scrollToAndHighlight(msg.replyToId!, messages);
                            }
                          },
                          onDelete: () async {
                            await ref.read(chatRepositoryProvider).deleteForMe(msg.id);
                            if (mounted) {
                              ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                              ref.read(conversationsProvider.notifier).loadConversations();
                            }
                          },
                          onSendReply: (replyText) async {
                            final chatRepo = ref.read(chatRepositoryProvider);
                            final replyPreview = _getMessageReplyPreview(msg);
                            await chatRepo.sendMessage(
                              conversationId: widget.conversationId,
                              content: replyText,
                              replyToId: msg.id,
                              replyToSender: msg.senderId == 'self' ? 'You' : msg.senderName,
                              replyToText: replyPreview,
                            );
                            if (mounted) {
                              ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                              ref.read(conversationsProvider.notifier).loadConversations();
                              _scrollToBottom();
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // Composer or Approval Bar
          if (_conversation?.requestStatus == 'pending_incoming')
            _buildApprovalBar()
          else if (_conversation?.requestStatus == 'pending_outgoing' &&
              messagesAsync.value != null &&
              messagesAsync.value!.any((m) => m.senderId == 'self'))
            _buildWaitingApprovalBar()
          else
            ChatComposer(
              replyToSender: _replyingMessage != null
                  ? (_replyingMessage!.senderId == 'self' ? 'You' : _replyingMessage!.senderName)
                  : null,
              replyToText: _replyingMessage != null ? _getMessageReplyPreview(_replyingMessage!) : null,
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

  Widget _buildApprovalBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This user wants to connect with you. Approve to start messaging.',
              style: TextStyle(fontSize: 13, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final chatRepo = ref.read(chatRepositoryProvider);
                      await chatRepo.denyConnection(widget.conversationId);
                      ref.invalidate(pendingRequestsProvider);
                      ref.invalidate(conversationsProvider);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request denied. User moved to Blocked list.'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      _handleBack(context);
                    },
                    child: const Text('Deny', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ultraviolet,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      final chatRepo = ref.read(chatRepositoryProvider);
                      await chatRepo.approveConnection(widget.conversationId);
                      ref.invalidate(pendingRequestsProvider);
                      ref.invalidate(conversationsProvider);
                      await _loadConversation();
                      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMessages();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request approved! You can now chat.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                    child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingApprovalBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.lavender.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: AppColors.ultraviolet.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded, color: AppColors.ultraviolet, size: 24),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Waiting for recipient to approve request. You can send more messages once approved.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

