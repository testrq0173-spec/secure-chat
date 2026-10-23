import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../data/models/group.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  Group? _group;
  List<GroupMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final db = ref.read(databaseServiceProvider);
    final g = await db.getGroup(widget.groupId);
    final m = await db.getGroupMembers(widget.groupId);
    if (mounted) {
      setState(() {
        _group = g;
        _members = m;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator(color: AppColors.ultraviolet)),
      );
    }

    if (_group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Group not found')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Header Card
            Center(
              child: Column(
                children: [
                  AppAvatar(name: _group!.name, radius: 46, isGroup: true),
                  const SizedBox(height: 16),
                  Text(_group!.name, style: AppTypography.title.copyWith(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text('${_members.length} members', style: AppTypography.caption),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Invite Link Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.grey200),
                boxShadow: AppColors.softCardShadow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: AppColors.ultraviolet, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Group Invite Link', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                        Text(_group!.inviteLink, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.ultraviolet),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _group!.inviteLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Group invite link copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text('MEMBERS (${_members.length})', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),

            // Members List
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.grey200),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _members.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final member = _members[index];
                  return ListTile(
                    leading: AppAvatar(name: member.displayName, radius: 18),
                    title: Text(member.displayName, style: AppTypography.bodyMedium),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: member.role == GroupRole.owner
                            ? AppColors.ultraviolet.withValues(alpha: 0.12)
                            : AppColors.grey200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        member.role.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: member.role == GroupRole.owner ? AppColors.ultraviolet : AppColors.grey500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // Leave Group Button
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Left group')),
                );
              },
              icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.error),
              label: const Text('Leave Group', style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
