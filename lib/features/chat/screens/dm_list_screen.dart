import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../../../models/dm_conversation.dart';
import '../../../models/friend.dart';
import '../../../services/chat_service.dart';
import '../../../services/friend_service.dart';

// Local provider: current user's accepted friends, used for display-name fallback
// when otherUserName is not yet denormalized on older conversation docs.
final _dmFriendsProvider = StreamProvider<List<Friend>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.id ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return ref.watch(friendServiceProvider).watchFriends(uid);
});

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
    return all
        .where(
          (c) => c.otherUserName.toLowerCase().contains(_query.toLowerCase()),
        )
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

class _ConvoTile extends ConsumerWidget {
  final DmConversation convo;
  final String myUid;
  final VoidCallback onTap;

  const _ConvoTile({
    required this.convo,
    required this.myUid,
    required this.onTap,
  });

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
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final hasUnread = convo.unreadCountForMe > 0;

    // CHANGED: resolve display name — otherUserName (denormalized) first,
    // then friends list fallback, then "Unknown User". Never show raw UID.
    final otherUid = _otherUid;
    String displayLabel = convo.otherUserName.isNotEmpty
        ? convo.otherUserName
        : '';
    if (displayLabel.isEmpty && otherUid.isNotEmpty) {
      final friends = ref.watch(_dmFriendsProvider).valueOrNull ?? const [];
      final match = friends.where((f) => f.friendUserId == otherUid).firstOrNull;
      displayLabel = match?.username ?? '';
    }
    // CHANGED: final fallback — never expose a raw Firestore UID to the user
    if (displayLabel.isEmpty) displayLabel = 'Unknown User';

    // CHANGED: initial letter comes from the resolved name, not the UID
    final initial = displayLabel[0].toUpperCase();

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
