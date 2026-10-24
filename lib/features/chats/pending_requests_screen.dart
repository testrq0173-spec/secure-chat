import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../data/models/conversation.dart';

class PendingRequestsScreen extends ConsumerWidget {
  const PendingRequestsScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Connection Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: requestsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.ultraviolet),
        ),
        error: (e, _) => Center(
          child: Text('Error loading requests: $e'),
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_disabled_rounded,
                      size: 48,
                      color: AppColors.ultraviolet,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('No Pending Requests', style: AppTypography.title),
                  const SizedBox(height: 8),
                  Text(
                    'When someone scans your QR or connects with your link,\ntheir request will appear here.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final conv = requests[index];
              return _buildRequestTile(context, ref, conv);
            },
          );
        },
      ),
    );
  }

  Widget _buildRequestTile(BuildContext context, WidgetRef ref, Conversation conv) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: AppAvatar(
          name: conv.title,
          radius: 24,
        ),
        title: Text(
          conv.title,
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              conv.lastMessageText?.isNotEmpty == true && conv.lastMessageText != 'New connection request'
                  ? conv.lastMessageText!
                  : 'Wants to connect with you',
              style: AppTypography.caption.copyWith(color: AppColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _formatTimestamp(conv.lastMessageTime),
              style: AppTypography.caption,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.grey500),
        onTap: () async {
          await context.push('/chat/${conv.id}');
          ref.invalidate(pendingRequestsProvider);
          ref.invalidate(conversationsProvider);
        },
      ),
    );
  }
}
