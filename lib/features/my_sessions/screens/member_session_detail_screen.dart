import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/core/utils/date_formatter.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/participant.dart';
import 'package:study_collab/models/session.dart';

class MemberSessionDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const MemberSessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<MemberSessionDetailScreen> createState() =>
      _MemberSessionDetailScreenState();
}

class _MemberSessionDetailScreenState
    extends ConsumerState<MemberSessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _sessionEndedPopupShown = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSessionEndedPopup(
    Session session,
    List<Participant> members,
    String currentUserId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _SessionEndedSheet(
        session: session,
        members: members,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionStreamProvider(widget.sessionId));
    final membersAsync = ref.watch(sessionMembersProvider(widget.sessionId));
    final currentUser = ref.watch(currentUserProvider).asData?.value;

    final members = membersAsync.asData?.value ?? [];
    final currentUserId = currentUser?.id ?? '';

    ref.listen(sessionStreamProvider(widget.sessionId), (prev, next) {
      final session = next.asData?.value;
      final prevSession = prev?.asData?.value;
      if (session != null &&
          session.status == SessionStatus.completed &&
          prevSession?.status != SessionStatus.completed &&
          !_sessionEndedPopupShown) {
        setState(() => _sessionEndedPopupShown = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showSessionEndedPopup(session, members, currentUserId);
        });
      }
    });

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
          return Column(
            children: [
              _MemberSessionInfoCard(session: session),
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
                tabs: const [Tab(text: 'Members'), Tab(text: 'Notes')],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _MemberMembersTab(
                      session: session,
                      members: members,
                      currentUserId: currentUserId,
                    ),
                    _MemberNotesTab(sessionId: widget.sessionId),
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

// ── Session info card (member view) ───────────────────────────────────────────

class _MemberSessionInfoCard extends StatelessWidget {
  final Session session;

  const _MemberSessionInfoCard({required this.session});

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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'Joined',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
          const SizedBox(height: 8),
          // Host row
          Row(
            children: [
              _ParticipantAvatar(
                username: session.hostName,
                photoUrl: session.hostPhotoUrl,
                radius: 12,
              ),
              const SizedBox(width: 6),
              Text(
                'Hosted by ${session.hostName}',
                style: const TextStyle(color: AppColors.hint, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

// ── Tab 1: Members (member view) ──────────────────────────────────────────────

class _MemberMembersTab extends StatelessWidget {
  final Session session;
  final List<Participant> members;
  final String currentUserId;

  const _MemberMembersTab({
    required this.session,
    required this.members,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final hostParticipant = members.where((m) => m.isHost).firstOrNull;
    final nonHostMembers = members.where((m) => !m.isHost).toList();
    final previewMembers = nonHostMembers.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
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

// ── Tab 2: Notes (identical to host's notes tab) ──────────────────────────────

class _MemberNotesTab extends StatelessWidget {
  final String sessionId;

  const _MemberNotesTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search notes...',
              prefixIcon: const Icon(Icons.search_outlined, color: AppColors.hint),
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

// ── Session Ended Bottom Sheet (member view) ──────────────────────────────────

class _SessionEndedSheet extends ConsumerStatefulWidget {
  final Session session;
  final List<Participant> members;
  final String currentUserId;

  const _SessionEndedSheet({
    required this.session,
    required this.members,
    required this.currentUserId,
  });

  @override
  ConsumerState<_SessionEndedSheet> createState() => _SessionEndedSheetState();
}

class _SessionEndedSheetState extends ConsumerState<_SessionEndedSheet> {
  final Map<String, bool> _thumbsUp = {};
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // Order: host → self (no thumbs-up) → others (thumbs-up toggle)
    final hostList = widget.members
        .where((m) => m.userId == widget.session.hostId)
        .toList();
    final selfList = widget.members
        .where(
          (m) =>
              m.userId == widget.currentUserId &&
              m.userId != widget.session.hostId,
        )
        .toList();
    final otherList = widget.members
        .where(
          (m) =>
              m.userId != widget.session.hostId &&
              m.userId != widget.currentUserId,
        )
        .toList();

    final sorted = [...hostList, ...selfList, ...otherList];
    final filtered = _searchQuery.isEmpty
        ? sorted
        : sorted
              .where(
                (m) => m.username.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();

    final totalCount = widget.members.length;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Top row: centered title + close button
              Row(
                children: [
                  const Spacer(),
                  const Text(
                    'Session Ended',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.hint),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Session name
              Text(
                widget.session.title,
                style: const TextStyle(color: AppColors.hint, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Description
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'There were $totalCount people in this room. Give a quick thumbs up to anyone you\'d like to study with again.',
                  style: const TextStyle(color: AppColors.text, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),

              // Search bar
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search participants by name',
                  prefixIcon: const Icon(
                    Icons.search_outlined,
                    color: AppColors.hint,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Participant list
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No participants found.',
                          style: TextStyle(
                            color: AppColors.hint,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          final isHost = p.userId == widget.session.hostId;
                          final isSelf = p.userId == widget.currentUserId;

                          if (isHost) {
                            return _HostParticipantTile(participant: p);
                          }
                          if (isSelf) {
                            return _SelfParticipantTile(participant: p);
                          }
                          return _RateableTile(
                            participant: p,
                            isThumbsUp: _thumbsUp[p.userId] ?? false,
                            onToggle: () => setState(() {
                              _thumbsUp[p.userId] =
                                  !(_thumbsUp[p.userId] ?? false);
                            }),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),

              // Submit button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ratings submitted!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
                child: const Text('Submit Rating'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Participant tile widgets ───────────────────────────────────────────────────

class _HostParticipantTile extends StatelessWidget {
  final Participant participant;

  const _HostParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _ParticipantAvatar(
        username: participant.username,
        photoUrl: participant.profilePhotoUrl,
        radius: 20,
      ),
      title: Text(
        participant.username,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Container(
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
    );
  }
}

class _SelfParticipantTile extends StatelessWidget {
  final Participant participant;

  const _SelfParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _ParticipantAvatar(
        username: participant.username,
        photoUrl: participant.profilePhotoUrl,
        radius: 20,
      ),
      title: Text(
        participant.username,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.hint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'ME',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RateableTile extends StatelessWidget {
  final Participant participant;
  final bool isThumbsUp;
  final VoidCallback onToggle;

  const _RateableTile({
    required this.participant,
    required this.isThumbsUp,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _ParticipantAvatar(
        username: participant.username,
        photoUrl: participant.profilePhotoUrl,
        radius: 20,
      ),
      title: Text(
        participant.username,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: IconButton(
        icon: Icon(
          isThumbsUp ? Icons.thumb_up : Icons.thumb_up_outlined,
          color: isThumbsUp ? AppColors.accent : AppColors.hint,
        ),
        onPressed: onToggle,
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
