import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/core/utils/date_formatter.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/dashboard/widgets/join_password_dialog.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/models/app_user.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/join_request.dart';
import 'package:study_collab/models/participant.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionStreamProvider(sessionId));

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _SessionNotFoundScaffold(message: error.toString()),
      data: (session) {
        if (session == null) {
          return const _SessionNotFoundScaffold(
            message: 'This session no longer exists.',
          );
        }
        return _SessionDetailBody(session: session);
      },
    );
  }
}

// ── Not-found scaffold ────────────────────────────────────────────────────────

class _SessionNotFoundScaffold extends StatelessWidget {
  final String message;
  const _SessionNotFoundScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Session'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.hint),
              const SizedBox(height: 16),
              const Text(
                'Session not found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.hint, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _SessionDetailBody extends ConsumerWidget {
  final Session session;
  const _SessionDetailBody({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(sessionMembersProvider(session.id));
    final requestsAsync = ref.watch(sessionRequestsProvider(session.id));
    final me = ref.watch(currentUserProvider).asData?.value;
    final isHost = me != null && me.id == session.hostId;
    // M4: Explicit binding — callerUid is only non-null when the current user
    // is the host; the `if (isHost)` guards below ensure it is never used as null.
    final callerUid = isHost ? me.id : null;

    final members = membersAsync.asData?.value ?? [];
    final requests = requestsAsync.asData?.value ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar ─────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.text,
              ),
              onPressed: () => context.pop(),
            ),
            title: Text(
              session.title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (isHost)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.text),
                  onPressed: () => context.push('/session/${session.id}/edit'),
                ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Subject pill + visibility chip ─────────────────────────
                  const SizedBox(height: 8),
                  _InfoChipsRow(session: session),
                  const SizedBox(height: 16),

                  // ── Title ──────────────────────────────────────────────────
                  Text(
                    session.title,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Host row ────────────────────────────────────────────────
                  _HostRow(session: session),
                  const SizedBox(height: 16),

                  // ── Info cards ──────────────────────────────────────────────
                  _InfoCard(
                    icon: Icons.calendar_today_outlined,
                    label: DateFormatter.relativeDate(session.startTime),
                    sub: DateFormatter.timeRange(
                      session.startTime,
                      session.endTime,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.location_on_outlined,
                    label: session.location,
                  ),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.group_outlined,
                    label:
                        '${session.participantCount} / ${session.capacity} members',
                    sub: session.isFull
                        ? 'Full'
                        : '${session.spotsLeft} spots left',
                  ),
                  const SizedBox(height: 16),

                  // ── Description ─────────────────────────────────────────────
                  if (session.description.isNotEmpty) ...[
                    const Text(
                      'About this session',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.description,
                      style: const TextStyle(
                        color: AppColors.hint,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Hashtags ────────────────────────────────────────────────
                  if (session.hashtags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: session.hashtags
                          .map((tag) => _HashtagChip(tag: tag))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Capacity progress bar ───────────────────────────────────
                  _CapacityBar(session: session),
                  const SizedBox(height: 24),

                  // ── Members section ─────────────────────────────────────────
                  _SectionHeader(
                    title: 'Members',
                    trailingLabel: members.length > 3 ? 'See All' : null,
                    onTrailingTap: members.length > 3
                        ? () => context.push('/session/${session.id}/members')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  membersAsync.when(
                    loading: () => const _LoadingRow(),
                    error: (_, _) =>
                        const _ErrorRow(message: 'Could not load members'),
                    data: (list) => _MembersPreviewRow(
                      members: list.take(5).toList(),
                      session: session,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Pending requests section (host-only) ────────────────────
                  if (isHost) ...[
                    _SectionHeader(
                      title: 'Requests',
                      trailingLabel: requests.length > 3 ? 'See All' : null,
                      onTrailingTap: requests.length > 3
                          ? () =>
                                context.push('/session/${session.id}/requests')
                          : null,
                    ),
                    const SizedBox(height: 8),
                    requestsAsync.when(
                      loading: () => const _LoadingRow(),
                      error: (_, _) =>
                          const _ErrorRow(message: 'Could not load requests'),
                      data: (list) {
                        if (list.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No pending requests.',
                              style: TextStyle(
                                color: AppColors.hint,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: list
                              .take(3)
                              .map(
                                (req) => _RequestTile(
                                  request: req,
                                  session: session,
                                  // callerUid is non-null here because this
                                  // block is inside `if (isHost)`.
                                  callerUid: callerUid!,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Action button row (non-host) ────────────────────────────
                  if (!isHost) _JoinActionRow(session: session, me: me),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info chips row (subject + visibility) ─────────────────────────────────────

class _InfoChipsRow extends StatelessWidget {
  final Session session;
  const _InfoChipsRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final visibilityLabel = session.visibility == SessionVisibility.private
        ? '🔒 Private'
        : '🌐 Public';

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        // Subject pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: session.subject.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: session.subject.color.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            session.subject.displayName,
            style: TextStyle(
              color: session.subject.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Visibility chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            visibilityLabel,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Host row ──────────────────────────────────────────────────────────────────

class _HostRow extends StatelessWidget {
  final Session session;
  const _HostRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final initial = session.hostName.isNotEmpty
        ? session.hostName[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () => context.push('/user/${session.hostId}'),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: session.subject.color.withValues(alpha: 0.15),
            backgroundImage:
                session.hostPhotoUrl != null && session.hostPhotoUrl!.isNotEmpty
                ? NetworkImage(session.hostPhotoUrl!)
                : null,
            child: session.hostPhotoUrl == null || session.hostPhotoUrl!.isEmpty
                ? Text(
                    initial,
                    style: TextStyle(
                      color: session.subject.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hosted by',
                style: TextStyle(color: AppColors.hint, fontSize: 11),
              ),
              Text(
                session.hostName,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  const _InfoCard({required this.icon, required this.label, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: const TextStyle(color: AppColors.hint, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hashtag chip ──────────────────────────────────────────────────────────────

class _HashtagChip extends StatelessWidget {
  final String tag;
  const _HashtagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── Capacity progress bar ─────────────────────────────────────────────────────

class _CapacityBar extends StatelessWidget {
  final Session session;
  const _CapacityBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final progress = session.capacity > 0
        ? (session.participantCount / session.capacity).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            color: AppColors.accent,
            backgroundColor: AppColors.secondary,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${session.spotsLeft} / ${session.capacity} spots remaining',
          style: const TextStyle(color: AppColors.hint, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;
  const _SectionHeader({
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailingLabel != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Text(
              trailingLabel!,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Members preview row ───────────────────────────────────────────────────────

class _MembersPreviewRow extends StatelessWidget {
  final List<Participant> members;
  final Session session;
  const _MembersPreviewRow({required this.members, required this.session});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Text(
        'No members yet.',
        style: TextStyle(color: AppColors.hint, fontSize: 13),
      );
    }
    return Row(
      children: [
        ...members.map(
          (m) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _MemberAvatar(participant: m),
          ),
        ),
      ],
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final Participant participant;
  const _MemberAvatar({required this.participant});

  @override
  Widget build(BuildContext context) {
    final initial = participant.username.isNotEmpty
        ? participant.username[0].toUpperCase()
        : '?';
    return Tooltip(
      message: participant.username,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.secondary,
        backgroundImage:
            participant.profilePhotoUrl != null &&
                participant.profilePhotoUrl!.isNotEmpty
            ? NetworkImage(participant.profilePhotoUrl!)
            : null,
        child:
            participant.profilePhotoUrl == null ||
                participant.profilePhotoUrl!.isEmpty
            ? Text(
                initial,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
    );
  }
}

// ── Request tile ──────────────────────────────────────────────────────────────

class _RequestTile extends ConsumerStatefulWidget {
  final JoinRequest request;
  final Session session;
  final String callerUid;

  const _RequestTile({
    required this.request,
    required this.session,
    required this.callerUid,
  });

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _approvingLoading = false;
  bool _decliningLoading = false;

  Future<void> _approve() async {
    setState(() => _approvingLoading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .approveRequest(
            session: widget.session,
            callerUid: widget.callerUid,
            requestUserId: widget.request.userId,
            requestUsername: widget.request.username,
            requestUserPhotoUrl: widget.request.profilePhotoUrl,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not approve request: ${e is AppException ? e.message : e.toString()}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _approvingLoading = false);
    }
  }

  Future<void> _decline() async {
    // H1-followup: guard against signed-out state before calling service.
    if (widget.callerUid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in')));
      return;
    }
    setState(() => _decliningLoading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .declineRequest(
            sessionId: widget.session.id,
            callerUid: widget.callerUid,
            userId: widget.request.userId,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not decline request: ${e is AppException ? e.message : e.toString()}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _decliningLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.request.username.isNotEmpty
        ? widget.request.username[0].toUpperCase()
        : '?';
    final isWorking = _approvingLoading || _decliningLoading;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.secondary,
            backgroundImage:
                widget.request.profilePhotoUrl != null &&
                    widget.request.profilePhotoUrl!.isNotEmpty
                ? NetworkImage(widget.request.profilePhotoUrl!)
                : null,
            child:
                widget.request.profilePhotoUrl == null ||
                    widget.request.profilePhotoUrl!.isEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.request.username,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  DateFormatter.relative(widget.request.requestedAt),
                  style: const TextStyle(color: AppColors.hint, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Decline button
          SizedBox(
            height: 32,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                foregroundColor: AppColors.error,
                minimumSize: const Size(70, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isWorking ? null : _decline,
              child: _decliningLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.error,
                      ),
                    )
                  : const Text('Decline', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          // Approve button
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(70, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isWorking ? null : _approve,
              child: _approvingLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Approve',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Join action row (non-host) ────────────────────────────────────────────────

class _JoinActionRow extends ConsumerWidget {
  final Session session;
  final AppUser? me;

  const _JoinActionRow({required this.session, required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (session.myStatus) {
      case JoinStatus.joined:
        return const _StatusChip(
          label: 'Joined ✓',
          backgroundColor: AppColors.success,
          textColor: Colors.white,
        );
      case JoinStatus.host:
        return const SizedBox.shrink();
      case JoinStatus.pending:
        return const _StatusChip(
          label: 'Pending...',
          backgroundColor: AppColors.warning,
          textColor: Colors.white,
        );
      case JoinStatus.notJoined:
        return _NotJoinedActions(session: session, me: me);
    }
  }
}

class _NotJoinedActions extends ConsumerStatefulWidget {
  final Session session;
  final AppUser? me;

  const _NotJoinedActions({required this.session, required this.me});

  @override
  ConsumerState<_NotJoinedActions> createState() => _NotJoinedActionsState();
}

class _NotJoinedActionsState extends ConsumerState<_NotJoinedActions> {
  bool _loading = false;

  Future<void> _requestJoin() async {
    final me = widget.me ?? ref.read(currentUserProvider).asData?.value;
    if (me == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .requestJoin(
            sessionId: widget.session.id,
            userId: me.id,
            username: me.username,
            profilePhotoUrl: me.profilePhotoUrl,
          );
      // Stream update from sessionStreamProvider will reflect pending status.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is DataException ? e.message : e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinWithPassword() async {
    final me = widget.me ?? ref.read(currentUserProvider).asData?.value;
    if (me == null) return;

    final password = await showDialog<String>(
      context: context,
      builder: (_) => JoinPasswordDialog(session: widget.session),
    );
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .joinWithPassword(
            session: widget.session,
            userId: me.id,
            username: me.username,
            profilePhotoUrl: me.profilePhotoUrl,
            plainTextPassword: password,
          );
      // Stream update will reflect joined status.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is DataException ? e.message : e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.visibility == SessionVisibility.private) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          minimumSize: const Size(double.infinity, 48),
        ),
        onPressed: _loading ? null : _joinWithPassword,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.lock_outline, size: 16),
        label: const Text('Join with Password'),
      );
    }

    // Public — request approval.
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        minimumSize: const Size(double.infinity, 48),
      ),
      onPressed: _loading ? null : _requestJoin,
      child: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Request to Join'),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Loading / error placeholders ──────────────────────────────────────────────

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.hint, fontSize: 13),
      ),
    );
  }
}
