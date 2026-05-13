import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/core/utils/date_formatter.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/models/join_request.dart';
import 'package:study_collab/models/participant.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';
import 'package:study_collab/services/session_service.dart';

// CHANGED: enum for host 3-dot menu actions
enum _HostAction { edit, delete, copyLink }

// ── Screen ─────────────────────────────────────────────────────────────────────

class HostSessionDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const HostSessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<HostSessionDetailScreen> createState() =>
      _HostSessionDetailScreenState();
}

class _HostSessionDetailScreenState
    extends ConsumerState<HostSessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionStreamProvider(widget.sessionId));
    final membersAsync = ref.watch(sessionMembersProvider(widget.sessionId));
    final requestsAsync = ref.watch(sessionRequestsProvider(widget.sessionId));
    final currentUser = ref.watch(currentUserProvider).asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7143BF), AppColors.accent],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Session Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        // CHANGED: 3-dot menu for Edit / Delete / Copy Link
        actions: [
          if (sessionAsync.asData?.value != null)
            PopupMenuButton<_HostAction>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (action) async {
                final session = sessionAsync.asData!.value!;
                switch (action) {
                  case _HostAction.edit:
                    context.push('/session/${session.id}/edit');

                  case _HostAction.delete:
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                          'Delete Session?',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                        content: Text(
                          'This will permanently remove the session and all its data. Members will be notified.',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE53E3E),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref.read(sessionServiceProvider).deleteSession(
                        sessionId: session.id,
                        hostId: session.hostId,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is AppException
                                ? e.message
                                : 'Failed to delete session',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Session deleted')),
                    );
                    context.pop();

                  case _HostAction.copyLink:
                    await Clipboard.setData(
                      ClipboardData(
                        text: 'studycollab://session/${session.id}',
                      ),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied!')),
                    );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HostAction.edit,
                  child: Text('✏️ Edit Session'),
                ),
                PopupMenuItem(
                  value: _HostAction.delete,
                  child: Text('🗑️ Delete Session'),
                ),
                PopupMenuItem(
                  value: _HostAction.copyLink,
                  child: Text('🔗 Copy Invite Link'),
                ),
              ],
            ),
        ],
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load session. Please try again.',
            style: TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ),
        data: (session) {
          if (session == null) {
            return const Center(
              child: Text(
                'Session not found.',
                style: TextStyle(color: AppColors.hint, fontSize: 14),
              ),
            );
          }
          final members = membersAsync.asData?.value ?? [];
          final requests = requestsAsync.asData?.value ?? [];
          return Column(
            children: [
              _SessionInfoCard(session: session),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.hint,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                tabs: const [
                  Tab(text: 'Members'),
                  Tab(text: 'Notes'),
                  Tab(text: 'Requests'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _MembersTab(
                      session: session,
                      members: members,
                      currentUserId: currentUser?.id ?? '',
                    ),
                    _NotesTab(sessionId: widget.sessionId),
                    _RequestsTab(
                      session: session,
                      requests: requests,
                      currentUserId: currentUser?.id ?? '',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Session info card ──────────────────────────────────────────────────────────

class _SessionInfoCard extends StatelessWidget {
  final Session session;

  const _SessionInfoCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final progress = session.capacity > 0
        ? (session.participantCount / session.capacity).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags row
          Row(
            children: [
              _SubjectChip(session: session),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Hosting',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Title
          Text(
            session.title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // Date row
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: AppColors.hint,
              ),
              const SizedBox(width: 6),
              Text(
                '${DateFormatter.relativeDate(session.startTime)}  ${DateFormatter.timeRange(session.startTime, session.endTime)}',
                style: const TextStyle(color: AppColors.hint, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Location row
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppColors.hint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  session.location,
                  style: const TextStyle(color: AppColors.hint, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Capacity row
          Row(
            children: [
              const Icon(Icons.group_outlined, size: 14, color: AppColors.hint),
              const SizedBox(width: 6),
              Text(
                '${session.participantCount}/${session.capacity} members',
                style: const TextStyle(color: AppColors.hint, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              color: AppColors.accent,
              backgroundColor: AppColors.secondary,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final Session session;

  const _SubjectChip({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

// ── Tab 1: Members ─────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final Session session;
  final List<Participant> members;
  final String currentUserId;

  const _MembersTab({
    required this.session,
    required this.members,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostParticipant = members.where((m) => m.isHost).firstOrNull;
    final nonHostMembers = members.where((m) => !m.isHost).toList();
    final previewMembers = nonHostMembers.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Host section
        const Text(
          'Host',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _HostRow(session: session, hostParticipant: hostParticipant),
        const SizedBox(height: 20),

        // Members section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Members (${nonHostMembers.length})',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/session/${session.id}/members'),
              child: const Text(
                'View all',
                style: TextStyle(color: AppColors.accent, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (nonHostMembers.isEmpty)
          const Text(
            'No members yet.',
            style: TextStyle(color: AppColors.hint, fontSize: 13),
          )
        else
          Row(
            children: previewMembers
                .map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ParticipantAvatar(
                      username: m.username,
                      photoUrl: m.profilePhotoUrl,
                      radius: 20,
                    ),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 32),

        // Message group button
        // CHANGED: End Session button removed — delete is now in the 3-dot menu
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Message group'),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Group messaging coming soon')),
            );
          },
        ),
      ],
    );
  }
}

class _HostRow extends StatelessWidget {
  final Session session;
  final Participant? hostParticipant;

  const _HostRow({required this.session, this.hostParticipant});

  @override
  Widget build(BuildContext context) {
    final name = hostParticipant?.username ?? session.hostName;
    final photoUrl = hostParticipant?.profilePhotoUrl ?? session.hostPhotoUrl;
    return Row(
      children: [
        _ParticipantAvatar(username: name, photoUrl: photoUrl, radius: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Host',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab 2: Notes ───────────────────────────────────────────────────────────────

class _NotesTab extends StatelessWidget {
  final String sessionId;

  const _NotesTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          // Search bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Search notes...',
              prefixIcon: const Icon(
                Icons.search_outlined,
                color: AppColors.hint,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Empty state
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 64,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No notes uploaded yet',
                    style: TextStyle(color: AppColors.hint, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          // Upload note button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Upload Note'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File upload coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Tab 3: Requests ────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  final Session session;
  final List<JoinRequest> requests;
  final String currentUserId;

  const _RequestsTab({
    required this.session,
    required this.requests,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Header with count badge
        Row(
          children: [
            const Text(
              'Pending requests',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${requests.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (requests.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No pending requests',
                    style: TextStyle(color: AppColors.hint, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...requests.map(
            (req) => _RequestCard(
              request: req,
              session: session,
              callerUid: currentUserId,
            ),
          ),
      ],
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final JoinRequest request;
  final Session session;
  final String callerUid;

  const _RequestCard({
    required this.request,
    required this.session,
    required this.callerUid,
  });

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
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
              'Could not approve: ${e is AppException ? e.message : e.toString()}',
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
    if (widget.callerUid.isEmpty) return;
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
              'Could not decline: ${e is AppException ? e.message : e.toString()}',
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
    final isWorking = _approvingLoading || _decliningLoading;
    final initial = widget.request.username.isNotEmpty
        ? widget.request.username[0].toUpperCase()
        : '?';

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
            radius: 20,
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
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
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

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _ParticipantAvatar extends StatelessWidget {
  final String username;
  final String? photoUrl;
  final double radius;

  const _ParticipantAvatar({
    required this.username,
    required this.photoUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.secondary,
      backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
          ? NetworkImage(photoUrl!)
          : null,
      child: photoUrl == null || photoUrl!.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: AppColors.accent,
                fontSize: radius * 0.65,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
