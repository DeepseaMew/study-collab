import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/app_user.dart';
import '../../../services/friend_service.dart';
import '../../../services/user_service.dart';
import '../../auth/providers/auth_providers.dart';

class OtherUserProfileScreen extends ConsumerWidget {
  final String userId;
  const OtherUserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final userAsync = ref.watch(_otherUserProvider(userId));
    final currentUserAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Failed to load profile: $e')),
      ),
      data: (user) {
        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('User not found')),
          );
        }
        return _buildContent(context, ref, tt, user, currentUserAsync.value);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TextTheme tt,
    AppUser user,
    AppUser? currentUser,
  ) {
    final initial =
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(user.username)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // Avatar + name + email
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor:
                      AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage: (user.profilePhotoUrl != null &&
                          user.profilePhotoUrl!.isNotEmpty)
                      ? NetworkImage(user.profilePhotoUrl!)
                      : null,
                  child: (user.profilePhotoUrl == null ||
                          user.profilePhotoUrl!.isEmpty)
                      ? Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(user.username, style: tt.displayMedium),
                const SizedBox(height: 2),
                Text(user.email,
                    style: tt.bodyMedium
                        ?.copyWith(color: AppColors.hint)),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    user.bio,
                    style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (user.faculty.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      user.faculty,
                      'Year ${user.studentYear}',
                      user.academicLevel.displayName,
                    ].join(' · '),
                    style: tt.labelLarge
                        ?.copyWith(color: AppColors.hint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Stats row — 3 columns: Sessions / Friends / Attended
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  label: 'Sessions',
                  value: user.sessionsCount.toString(),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                _StatItem(
                  label: 'Friends',
                  value: user.friendsCount.toString(),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                // TODO: wire to participation_service when ready
                const _StatItem(label: 'Attended', value: '0'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons — only show if viewing someone else's profile
          if (currentUser != null && currentUser.id != user.id)
            _FriendActions(currentUser: currentUser, otherUser: user),
          const SizedBox(height: 28),
          // Sessions section — empty for now, real data wired later
          Text(
            "Sessions by ${user.username.split(' ').first}",
            style: tt.titleLarge,
          ),
          const SizedBox(height: 12),
          const _NoPublicSessions(),
        ],
      ),
    );
  }
}

// ── Friend / message action row ───────────────────────────────────────────────

class _FriendActions extends ConsumerWidget {
  const _FriendActions({required this.currentUser, required this.otherUser});

  final AppUser currentUser;
  final AppUser otherUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_friendshipStatusProvider((
      currentUserId: currentUser.id,
      otherUserId: otherUser.id,
    )));

    return Row(
      children: [
        Expanded(
          child: statusAsync.when(
            loading: () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => OutlinedButton(
              onPressed: null,
              child: Text('Error: $e'),
            ),
            data: (status) => _FriendButton(
              status: status,
              currentUser: currentUser,
              otherUser: otherUser,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: statusAsync.maybeWhen(
            data: (status) {
              final canChat = status == FriendshipStatus.friends;
              return ElevatedButton.icon(
                onPressed: canChat
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Messaging coming soon')),
                        );
                      }
                    : null,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Message'),
              );
            },
            orElse: () => const ElevatedButton(
              onPressed: null,
              child: Text('Message'),
            ),
          ),
        ),
      ],
    );
  }
}

class _FriendButton extends ConsumerStatefulWidget {
  const _FriendButton({
    required this.status,
    required this.currentUser,
    required this.otherUser,
  });

  final FriendshipStatus status;
  final AppUser currentUser;
  final AppUser otherUser;

  @override
  ConsumerState<_FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends ConsumerState<_FriendButton> {
  bool _busy = false;

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successMsg,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (successMsg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndUnfriend(Future<void> Function() onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
            '${widget.otherUser.username} will no longer be able to message you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(friendServiceProvider);
    final me = widget.currentUser;
    final them = widget.otherUser;

    switch (widget.status) {
      case FriendshipStatus.self:
        return const SizedBox.shrink();

      case FriendshipStatus.friends:
        return OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _confirmAndUnfriend(
                    () => _runAction(
                      () => svc.unfriend(
                        currentUserId: me.id,
                        otherUserId: them.id,
                      ),
                    ),
                  ),
          icon: const Icon(Icons.people, size: 18),
          label: const Text('Friends'),
        );

      case FriendshipStatus.requestSent:
        return OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _runAction(
                    () => svc.cancelRequest(
                      fromUserId: me.id,
                      toUserId: them.id,
                    ),
                  ),
          icon: const Icon(Icons.hourglass_empty_outlined, size: 18),
          label: const Text('Request Sent'),
        );

      case FriendshipStatus.requestReceived:
        return ElevatedButton.icon(
          onPressed: _busy
              ? null
              : () => _runAction(
                    () => svc.acceptRequest(
                      currentUser: me,
                      fromUser: them,
                    ),
                    successMsg: 'You are now friends',
                  ),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Accept Request'),
        );

      case FriendshipStatus.notFriends:
        return OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _runAction(
                    () => svc.sendRequest(fromUser: me, toUser: them),
                    successMsg: 'Friend request sent',
                  ),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Friend'),
        );
    }
  }
}

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value,
            style: tt.displayMedium?.copyWith(color: AppColors.accent)),
        const SizedBox(height: 2),
        Text(label, style: tt.bodyMedium?.copyWith(color: AppColors.hint)),
      ],
    );
  }
}

class _NoPublicSessions extends StatelessWidget {
  const _NoPublicSessions();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.event_busy_outlined,
                size: 48, color: AppColors.disabled),
            const SizedBox(height: 12),
            Text('No public sessions',
                style: tt.bodyMedium?.copyWith(color: AppColors.hint)),
          ],
        ),
      ),
    );
  }
}

// ── Local providers ───────────────────────────────────────────────────────────

/// Streams another user's profile from Firestore, keyed by their userId.
final _otherUserProvider =
    StreamProvider.family<AppUser?, String>((ref, userId) {
  return ref.watch(userServiceProvider).watchUser(userId);
});

/// Streams the friendship status between current user and other user.
final _friendshipStatusProvider = StreamProvider.family<FriendshipStatus,
    ({String currentUserId, String otherUserId})>((ref, ids) {
  return ref.watch(friendServiceProvider).watchFriendshipStatus(
        currentUserId: ids.currentUserId,
        otherUserId: ids.otherUserId,
      );
});