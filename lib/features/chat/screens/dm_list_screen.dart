import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../../../models/dm_conversation.dart';
import '../../../services/chat_service.dart';

class DmListScreen extends ConsumerStatefulWidget {
  const DmListScreen({super.key});

  @override
  ConsumerState<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends ConsumerState<DmListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DmConversation> _filtered(List<DmConversation> all) {
    if (_query.isEmpty) return all;
    // Filter by otherParticipantId since userName is not denormalized on DM docs.
    // TODO(firebase-specialist): denormalize otherUserName on chats doc so
    //   search works by display name rather than uid.
    return all
        .where((c) => c.id.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  Future<void> _onTap(DmConversation convo, String myUid) async {
    // Fire-and-forget: mark read before navigating.
    unawaited(
      ref
          .read(chatServiceProvider)
          .markDmRead(conversationId: convo.id, userId: myUid),
    );
    if (mounted) {
      context.push('/messages/dm/${convo.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncConvos = ref.watch(userDmConversationsProvider);
    final myUid = ref.watch(authStateProvider).valueOrNull?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Messages')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: Icon(Icons.search, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: asyncConvos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Could not load conversations. Please try again.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (convos) {
                final filtered = _filtered(convos);
                if (filtered.isEmpty) {
                  return _EmptyState(hasQuery: _query.isNotEmpty);
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, i) => const Divider(
                    height: 1,
                    indent: 76,
                    color: AppColors.border,
                  ),
                  itemBuilder: (ctx, i) => _ConvoTile(
                    convo: filtered[i],
                    myUid: myUid,
                    onTap: () => _onTap(filtered[i], myUid),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Conversation tile ─────────────────────────────────────────────────────────

class _ConvoTile extends StatelessWidget {
  final DmConversation convo;
  final String myUid;
  final VoidCallback onTap;

  const _ConvoTile({
    required this.convo,
    required this.myUid,
    required this.onTap,
  });

  /// Derive the other participant's uid from the conversation id.
  String get _otherUid {
    if (myUid.isEmpty) return '';
    return convo.participantIds.firstWhere(
      (id) => id != myUid,
      orElse: () => '',
    );
  }

  String _timeLabel(DateTime dt) {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = DateUtils.dateOnly(dt);
    if (d == today) return DateFormat('h:mm a').format(dt);
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasUnread = convo.unreadCountForMe > 0;
    // Display the other user's uid initials until firebase-specialist
    // denormalizes the display name onto the chats doc (see follow-ups).
    final displayLabel = _otherUid.isNotEmpty ? _otherUid : convo.id;
    final initial = displayLabel.isNotEmpty
        ? displayLabel[0].toUpperCase()
        : '?';

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.secondary,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          if (hasUnread)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${convo.unreadCountForMe}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        displayLabel,
        style: tt.labelLarge?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        convo.lastMessageText ?? '',
        style: tt.bodyMedium?.copyWith(
          color: hasUnread ? AppColors.text : AppColors.hint,
          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: convo.lastMessageAt != null
          ? Text(_timeLabel(convo.lastMessageAt!), style: tt.labelSmall)
          : null,
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 36,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'No results found' : 'No messages yet',
            style: tt.displaySmall,
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Try a different name'
                : "Start a conversation from someone's profile",
            style: tt.bodyMedium?.copyWith(color: AppColors.hint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
