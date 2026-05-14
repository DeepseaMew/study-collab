import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../../../models/dm_conversation.dart';
import '../../../models/group_conversation.dart';
import '../../../services/chat_service.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dmUnread = ref.watch(unreadDmTotalProvider);
    final grpUnread = ref.watch(unreadGroupTotalProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text('Messages'),
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(92),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
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
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Individual'),
                        if (dmUnread > 0) ...[
                          const SizedBox(width: 6),
                          _UnreadBadge(count: dmUnread),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Groups'),
                        if (grpUnread > 0) ...[
                          const SizedBox(width: 6),
                          _UnreadBadge(count: grpUnread),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _IndividualTab(query: _query),
          const _GroupsTab(),
        ],
      ),
    );
  }
}

// ── Unread badge ──────────────────────────────────────────────────────────────

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Individual Tab ────────────────────────────────────────────────────────────

class _IndividualTab extends ConsumerWidget {
  final String query;
  const _IndividualTab({required this.query});

  List<DmConversation> _filtered(List<DmConversation> all) {
    if (query.isEmpty) return all;
    // TODO(firebase-specialist): filter by display name once it is
    // denormalized on the chats doc; for now filter by conversation id.
    return all
        .where((c) => c.id.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConvos = ref.watch(userDmConversationsProvider);
    final myUid = ref.watch(authStateProvider).valueOrNull?.id ?? '';

    return asyncConvos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: 'Could not load conversations. Please try again.',
      ),
      data: (convos) {
        final filtered = _filtered(convos);

        if (filtered.isEmpty) {
          return _EmptyState(
            icon: Icons.chat_bubble_outline,
            title: query.isNotEmpty
                ? 'No results found'
                : 'No conversations yet',
            subtitle: query.isNotEmpty
                ? 'Try a different name'
                : "Start a chat from someone's profile page",
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: filtered.length,
          separatorBuilder: (_, i) =>
              const Divider(height: 1, indent: 76, color: AppColors.border),
          itemBuilder: (ctx, i) {
            final c = filtered[i];
            // Derive the other user's uid from participantIds.
            final otherUid = c.participantIds.firstWhere(
              (id) => id != myUid,
              orElse: () => c.id,
            );
            return _DmTile(
              convo: c,
              displayLabel: otherUid,
              myUid: myUid,
              timeAgo: c.lastMessageAt != null
                  ? _timeAgo(c.lastMessageAt!)
                  : '',
              onTap: () async {
                try {
                  await ref
                      .read(chatServiceProvider)
                      .markDmRead(conversationId: c.id, userId: myUid);
                } catch (_) {
                  // Ignore mark-read errors; still navigate.
                }
                if (context.mounted) {
                  context.push('/messages/dm/${c.id}');
                }
              },
            );
          },
        );
      },
    );
  }
}

class _DmTile extends StatelessWidget {
  final DmConversation convo;
  final String displayLabel;
  final String myUid;
  final String timeAgo;
  final VoidCallback onTap;

  const _DmTile({
    required this.convo,
    required this.displayLabel,
    required this.myUid,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasUnread = convo.unreadCountForMe > 0;
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayLabel,
              style: tt.labelLarge?.copyWith(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (timeAgo.isNotEmpty)
            Text(
              timeAgo,
              style: tt.labelSmall?.copyWith(
                color: hasUnread ? AppColors.accent : AppColors.hint,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              convo.lastMessageText ?? '',
              style: tt.bodyMedium?.copyWith(
                color: hasUnread ? AppColors.text : AppColors.hint,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasUnread)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '${convo.unreadCountForMe} DM${convo.unreadCountForMe > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Groups Tab ────────────────────────────────────────────────────────────────

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(userGroupConversationsProvider);

    return asyncGroups.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: 'Could not load group chats. Please try again.',
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            title: 'No group chats yet',
            subtitle: 'Join a session to access its group chat',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: groups.length,
          separatorBuilder: (_, i) =>
              const Divider(height: 1, indent: 76, color: AppColors.border),
          itemBuilder: (ctx, i) {
            final g = groups[i];
            return _GroupTile(
              group: g,
              timeAgo: g.lastMessageAt != null
                  ? _timeAgo(g.lastMessageAt!)
                  : '',
              onTap: () => context.push('/session/${g.sessionId}/chat'),
            );
          },
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  final GroupConversation group;
  final String timeAgo;
  final VoidCallback onTap;

  const _GroupTile({
    required this.group,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasUnread = group.unreadCountForMe > 0;
    final initial = group.sessionTitle.isNotEmpty
        ? group.sessionTitle[0].toUpperCase()
        : 'G';

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
                    '${group.unreadCountForMe}',
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              group.sessionTitle,
              style: tt.labelLarge?.copyWith(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeAgo.isNotEmpty)
            Text(
              timeAgo,
              style: tt.labelSmall?.copyWith(
                color: hasUnread ? AppColors.accent : AppColors.hint,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              group.lastMessageText ?? 'No messages yet',
              style: tt.bodyMedium?.copyWith(
                color: hasUnread ? AppColors.text : AppColors.hint,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: group.sessionSubject.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              group.sessionSubject.displayName,
              style: tt.labelSmall?.copyWith(
                color: group.sessionSubject.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

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
            child: Icon(icon, size: 36, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text(title, style: tt.displaySmall),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: tt.bodyMedium?.copyWith(color: AppColors.hint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
