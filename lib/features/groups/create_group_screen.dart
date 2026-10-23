import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../data/models/contact.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedContactIds = {};
  List<Contact> _contacts = [];
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final db = ref.read(databaseServiceProvider);
    final list = await db.getAllContacts();
    if (mounted) {
      setState(() {
        _contacts = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final group = await chatRepo.createGroup(
        name: name,
        memberContactIds: _selectedContactIds.toList(),
      );

      ref.read(conversationsProvider.notifier).loadConversations();

      if (!mounted) return;
      context.go('/chat/${group.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Create New Group'),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: AppColors.ultraviolet, strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Group Name Input Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.grey200),
                boxShadow: AppColors.softCardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppColors.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_rounded, color: AppColors.ultraviolet, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Group Name',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Select Contacts Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text('SELECT MEMBERS', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_selectedContactIds.length} selected', style: AppTypography.caption),
                ],
              ),
            ),

            // Contacts Selection List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.ultraviolet))
                  : _contacts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No contacts available to add yet. Connect with people first!',
                              textAlign: TextAlign.center,
                              style: AppTypography.caption,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _contacts.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            final isSelected = _selectedContactIds.contains(contact.id);

                            return CheckboxListTile(
                              tileColor: AppColors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: AppColors.grey200),
                              ),
                              value: isSelected,
                              activeColor: AppColors.ultraviolet,
                              secondary: AppAvatar(
                                name: contact.displayName,
                                radius: 20,
                                isVerified: contact.isVerified,
                              ),
                              title: Text(contact.displayName, style: AppTypography.bodyMedium),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedContactIds.add(contact.id);
                                  } else {
                                    _selectedContactIds.remove(contact.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
