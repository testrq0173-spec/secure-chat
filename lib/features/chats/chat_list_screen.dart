import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../data/models/conversation.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0; // 0: All, 1: Direct, 2: Groups, 3: Saved Notes
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search chats & messages...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              )
            : Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.ultraviolet,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_rounded, color: AppColors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Bharosa'),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'New Group',
            onPressed: () => context.push('/create-group'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(index: 0, label: 'All Chats'),
                  _filterChip(index: 1, label: 'Direct'),
                  _filterChip(index: 2, label: 'Groups'),
                  _filterChip(index: 3, label: 'Saved Notes'),
                ],
              ),
            ),
          ),

          // Conversation List
          Expanded(
            child: conversationsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.ultraviolet),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (conversations) {
                // Apply Search Filter
                var list = conversations;
                final query = _searchController.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  list = list.where((c) {
                    final titleMatch = c.title.toLowerCase().contains(query);
                    final msgMatch = (c.lastMessageText ?? '').toLowerCase().contains(query);
                    return titleMatch || msgMatch;
                  }).toList();
                }

                // Apply Tab Filter
                if (_selectedFilterIndex == 1) {
                  list = list.where((c) => c.type == ConversationType.direct).toList();
                } else if (_selectedFilterIndex == 2) {
                  list = list.where((c) => c.type == ConversationType.group).toList();
                } else if (_selectedFilterIndex == 3) {
                  list = list.where((c) => c.type == ConversationType.notes).toList();
                }

                if (list.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  itemCount: list.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final conv = list[index];
                    return _buildConversationTile(conv);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ultraviolet,
        foregroundColor: AppColors.white,
        elevation: 4,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('New Connection', style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => context.push('/new-connection'),
      ),
    );
  }

  Widget _filterChip({required int index, required String label}) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.ultraviolet : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.ultraviolet : AppColors.grey200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(Conversation conv) {
    return InkWell(
      onTap: () => context.push('/chat/${conv.id}'),
      onLongPress: () => _showConversationOptions(conv),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppColors.softCardShadow,
          border: Border.all(color: AppColors.grey200.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            AppAvatar(
              name: conv.title,
              radius: 26,
              isVerified: conv.isVerified,
              isGroup: conv.type == ConversationType.group,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.title,
                          style: AppTypography.title.copyWith(fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.disappearingDurationSeconds > 0) ...[
                        const Icon(Icons.timer_outlined, size: 14, color: AppColors.warning),
                        const SizedBox(width: 4),
                      ],
                      if (conv.isMuted) ...[
                        const Icon(Icons.volume_off_rounded, size: 14, color: AppColors.grey500),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _formatTimestamp(conv.lastMessageTime),
                        style: AppTypography.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.draftText != null && conv.draftText!.isNotEmpty
                              ? 'Draft: ${conv.draftText}'
                              : (conv.lastMessageText ?? 'No messages yet'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: conv.draftText != null && conv.draftText!.isNotEmpty
                                ? AppColors.error
                                : AppColors.grey500,
                            fontWeight: conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: const BoxDecoration(
                            color: AppColors.ultraviolet,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            conv.unreadCount.toString(),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConversationOptions(Conversation conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bottomSheet)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  conv.isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: AppColors.ink,
                ),
                title: Text(conv.isMuted ? 'Unmute' : 'Mute Notifications'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(conversationsProvider.notifier).toggleMute(conv.id, conv.isMuted);
                },
              ),
              ListTile(
                leading: Icon(
                  conv.isArchived ? Icons.unarchive_rounded : Icons.archive_outlined,
                  color: AppColors.ink,
                ),
                title: Text(conv.isArchived ? 'Unarchive' : 'Archive Chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(conversationsProvider.notifier).toggleArchive(conv.id, conv.isArchived);
                },
              ),
              if (conv.type == ConversationType.direct)
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined, color: AppColors.success),
                  title: const Text('Verify Security Code'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/security-code/${conv.id}');
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.lavender,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.ultraviolet, size: 40),
            ),
            const SizedBox(height: 20),
            Text('No Conversations Yet', style: AppTypography.title),
            const SizedBox(height: 8),
            Text(
              'Create an invite link or scan a friend’s QR code to start an end-to-end encrypted chat.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}
