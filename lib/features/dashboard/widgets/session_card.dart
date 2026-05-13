import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/enums.dart';
import '../../../models/session.dart';
// CHANGED: providers for join / cancel actions and current user
import '../../auth/providers/auth_providers.dart';
import '../providers/dashboard_providers.dart';
import 'join_password_dialog.dart';
import 'join_request_dialog.dart';

class SessionCard extends StatelessWidget {
  final Session session;
  const SessionCard({super.key, required this.session});

  static const Color _joinColor = Color(0xFF5186CD);
  static const Color _progressColor = Color(0xFF5186CD);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isPrivate = session.visibility == SessionVisibility.private;
    final remaining = session.capacity - session.participantCount;
    final progress = session.capacity > 0
        ? (session.participantCount / session.capacity).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => context.push('/session/${session.id}'),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            // CHANGED: amber left border when pending
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: session.myStatus == JoinStatus.pending
                  ? const Border(
                      left: BorderSide(color: Color(0xFFD69E2E), width: 3),
                      right: BorderSide(color: AppColors.border),
                      top: BorderSide(color: AppColors.border),
                      bottom: BorderSide(color: AppColors.border),
                    )
                  : Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: subject pill + title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubjectPill(
                      label: session.subject.displayName,
                      color: session.subject.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        // CHANGED: extra right padding keeps title clear of pending chip
                        padding: EdgeInsets.only(
                          right: session.myStatus == JoinStatus.pending
                              ? 80
                              : isPrivate
                                  ? 20
                                  : 0,
                        ),
                        child: Text(
                          session.title,
                          style: tt.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Host row — avatar + name navigate to host profile
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/user/${session.hostId}'),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HostAvatar(
                            name: session.hostName,
                            avatarUrl: session.hostPhotoUrl ?? '',
                            color: session.subject.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            session.hostName,
                            style: tt.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(session.startTime),
                      style: tt.labelSmall?.copyWith(color: AppColors.hint),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Location row
                Row(
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        session.location,
                        style: tt.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Description (Session.description is non-null but can be empty)
                if (session.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    session.description,
                    style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    color: _progressColor,
                    backgroundColor: AppColors.secondary,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$remaining / ${session.capacity} spots remaining',
                  style: tt.labelSmall,
                ),
                const SizedBox(height: 12),
                // Join button area
                Align(
                  alignment: Alignment.centerRight,
                  child: _JoinArea(session: session, joinColor: _joinColor),
                ),
              ],
            ),
          ),
          // Lock badge for private sessions
          if (isPrivate)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.hint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: AppColors.hint,
                ),
              ),
            ),
          // CHANGED: pending chip — shown instead of lock (public sessions only)
          if (session.myStatus == JoinStatus.pending)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAEEDA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '⏳ Pending',
                  style: TextStyle(
                    color: Color(0xFF854F0B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Uses your DateFormatter helpers — relative date + 24h time.
  /// Output examples: "Today · 14:00", "Tomorrow · 10:00", "05/06/2025 · 15:30".
  String _formatDate(DateTime start) {
    final dateStr = DateFormatter.relativeDate(start);
    final timeStr = DateFormatter.time(start);
    return '$dateStr · $timeStr';
  }
}

// ── Private helper widgets ───────────────────────────────────────────────────

class _SubjectPill extends StatelessWidget {
  final String label;
  final Color color;
  const _SubjectPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HostAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final Color color;
  const _HostAvatar({
    required this.name,
    required this.avatarUrl,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.15),
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class _JoinArea extends StatelessWidget {
  final Session session;
  final Color joinColor;
  const _JoinArea({required this.session, required this.joinColor});

  @override
  Widget build(BuildContext context) {
    switch (session.myStatus) {
      case JoinStatus.joined:
        return const _StatusChip(
          label: 'Joined ✓',
          backgroundColor: AppColors.success,
          textColor: Colors.white,
        );
      // CHANGED: replaced _StatusChip with _HostBadge for the host state
      case JoinStatus.host:
        return const _HostBadge();
      // CHANGED: replaced static chip with interactive cancel + pending indicator
      case JoinStatus.pending:
        return _PendingButtons(session: session);
      case JoinStatus.notJoined:
        return _NotJoinedButton(session: session, joinColor: joinColor);
    }
  }
}

// CHANGED: converted to ConsumerStatefulWidget to wire sendJoinRequest
class _NotJoinedButton extends ConsumerStatefulWidget {
  final Session session;
  final Color joinColor;
  const _NotJoinedButton({required this.session, required this.joinColor});

  @override
  ConsumerState<_NotJoinedButton> createState() => _NotJoinedButtonState();
}

class _NotJoinedButtonState extends ConsumerState<_NotJoinedButton> {
  bool _busy = false;

  Future<void> _sendRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => JoinRequestDialog(session: widget.session),
    );
    if (confirmed != true || !mounted) return;

    final me = ref.read(currentUserProvider).asData?.value;
    if (me == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(sessionJoinActionsProvider).sendJoinRequest(
            sessionId: widget.session.id,
            userId: me.id,
            username: me.username,
            profilePhotoUrl: me.profilePhotoUrl,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Request sent! Waiting for host approval'),
          backgroundColor: Color(0xFF38A169),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.session.visibility) {
      case SessionVisibility.public:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: widget.joinColor),
            foregroundColor: widget.joinColor,
            minimumSize: const Size(120, 40),
          ),
          onPressed: _busy ? null : _sendRequest,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.joinColor,
                  ),
                )
              : const Text('Request to Join'),
        );

      // Private sessions are hidden from browse; reached via shared link only.
      case SessionVisibility.private:
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.joinColor,
            minimumSize: const Size(140, 40),
          ),
          onPressed: _busy
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final password = await showDialog<String>(
                    context: context,
                    builder: (_) =>
                        JoinPasswordDialog(session: widget.session),
                  );
                  if (password != null && mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Joined "${widget.session.title}"!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.lock_outline, size: 14),
          label: const Text('Join with Password'),
        );
    }
  }
}

// CHANGED: new widget — Cancel button + disabled Pending indicator
class _PendingButtons extends ConsumerStatefulWidget {
  final Session session;
  const _PendingButtons({required this.session});

  @override
  ConsumerState<_PendingButtons> createState() => _PendingButtonsState();
}

class _PendingButtonsState extends ConsumerState<_PendingButtons> {
  bool _busy = false;

  Future<void> _cancel() async {
    final me = ref.read(currentUserProvider).asData?.value;
    if (me == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionJoinActionsProvider).cancelJoinRequest(
            sessionId: widget.session.id,
            userId: me.id,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.error),
            foregroundColor: AppColors.error,
            minimumSize: const Size(80, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: _busy ? null : _cancel,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.error,
                  ),
                )
              : const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAEEDA),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text(
            '⏳ Pending...',
            style: TextStyle(
              color: Color(0xFF854F0B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  const _StatusChip({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// CHANGED: new host badge widget replacing the old _StatusChip host case
class _HostBadge extends StatelessWidget {
  const _HostBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text('👑', style: TextStyle(fontSize: 10)),
          SizedBox(width: 4),
          Text(
            'Your session',
            style: TextStyle(
              color: Color(0xFF3D6FB7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
