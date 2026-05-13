import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_user.dart';
import '../../../models/friend.dart';
import '../../../services/friend_service.dart';
import '../../../services/user_service.dart';

class FriendsListScreen extends ConsumerStatefulWidget {
  final String userId;
  const FriendsListScreen({super.key, required this.userId});

  @override
  ConsumerState<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends ConsumerState<FriendsListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Friend> _filter(List<Friend> friends) {
    if (_query.isEmpty) return friends;
    return friends
        .where((f) =>
            f.username.toLowerCase().contains(_query) ||
            (f.bio?.toLowerCase().contains(_query) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final userAsync = ref.watch(_friendsScreenProfileProvider(widget.userId));
    final friendsAsync = ref.watch(_friendsListProvider(widget.userId));

    final ownerName = userAsync.maybeWhen(
      data: (u) => u?.username,
      orElse: () => null,
    );
    final totalCount = friendsAsync.maybeWhen(
      data: (f) => f.length,
      orElse: () => null,
    );

    final parts = [
      ownerName != null ? "$ownerName's Friends" : 'Friends',
      if (totalCount != null) '· $totalCount',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(parts.join(' '), style: tt.headlineSmall),
      ),
      body: Column(
        children: [
          // CHANGED: search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          // CHANGED: friends list
          Expanded(
            child: friendsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (friends) {
                final filtered = _filter(friends);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No friends yet'
                          : "No friends match '$_query'",
                      style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, i) => const Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: Color(0xFFF0F0F0),
                  ),
                  itemBuilder: (context, i) => _FriendRow(friend: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final Friend friend;
  const _FriendRow({required this.friend});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final initial = friend.username.isNotEmpty
        ? friend.username[0].toUpperCase()
        : '?';
    final hasBio = friend.bio != null && friend.bio!.isNotEmpty;

    return InkWell(
      onTap: () => context.push('/user/${friend.friendUserId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              backgroundImage: (friend.profilePhotoUrl != null &&
                      friend.profilePhotoUrl!.isNotEmpty)
                  ? NetworkImage(friend.profilePhotoUrl!)
                  : null,
              child: (friend.profilePhotoUrl == null ||
                      friend.profilePhotoUrl!.isEmpty)
                  ? Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.username, style: tt.titleLarge),
                  if (hasBio)
                    Text(
                      friend.bio!,
                      style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // CHANGED: DM chip — purple fill, chat_bubble_outline icon, no border
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Messaging coming soon')),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DM',
                      style: tt.labelSmall?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local providers ────────────────────────────────────────────────────────────

final _friendsListProvider = StreamProvider.family<List<Friend>, String>((
  ref,
  userId,
) {
  return ref.watch(friendServiceProvider).watchFriends(userId);
});

final _friendsScreenProfileProvider = StreamProvider.family<AppUser?, String>((
  ref,
  userId,
) {
  return ref.watch(userServiceProvider).watchUser(userId);
});
