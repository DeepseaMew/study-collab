import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/enums.dart';
import '../../../models/session.dart';
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
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
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
                        padding: EdgeInsets.only(right: isPrivate ? 20 : 0),
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
                  child: _JoinArea(
                    session: session,
                    joinColor: _joinColor,
                  ),
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
                child: const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.hint),
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
      case JoinStatus.host:
        return const _StatusChip(
          label: 'You\'re the Host',
          backgroundColor: AppColors.accent,
          textColor: Colors.white,
        );
      case JoinStatus.pending:
        return const _StatusChip(
          label: 'Pending...',
          backgroundColor: AppColors.warning,
          textColor: Colors.white,
        );
      case JoinStatus.notJoined:
        return _NotJoinedButton(session: session, joinColor: joinColor);
    }
  }
}

class _NotJoinedButton extends StatelessWidget {
  final Session session;
  final Color joinColor;
  const _NotJoinedButton({required this.session, required this.joinColor});

  @override
  Widget build(BuildContext context) {
    switch (session.visibility) {
      case SessionVisibility.public:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: joinColor,
            minimumSize: const Size(80, 40),
          ),
          onPressed: () {
            // TODO: wire to participation_service.joinSession
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Joined "${session.title}"!'),
                backgroundColor: AppColors.success,
              ),
            );
          },
          child: const Text('Join'),
        );

      case SessionVisibility.approval:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: joinColor),
            foregroundColor: joinColor,
            minimumSize: const Size(120, 40),
          ),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => JoinRequestDialog(session: session),
            );
            if (confirmed == true && context.mounted) {
              // TODO: wire to participation_service.requestJoin
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Request sent!'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          child: const Text('Request to Join'),
        );

      case SessionVisibility.private:
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: joinColor,
            minimumSize: const Size(140, 40),
          ),
          onPressed: () async {
            final password = await showDialog<String>(
              context: context,
              builder: (_) => JoinPasswordDialog(session: session),
            );
            if (password != null && context.mounted) {
              // TODO: wire to participation_service.joinWithPassword
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Joined "${session.title}"!'),
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
