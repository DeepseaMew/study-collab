import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
// CHANGED: myPendingSessionsProvider for Upcoming tab
import 'package:study_collab/features/dashboard/providers/dashboard_providers.dart';
import 'package:study_collab/features/dashboard/widgets/search_bottom_sheet.dart';
import 'package:study_collab/features/dashboard/widgets/session_card.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';

class MySessionsScreen extends ConsumerStatefulWidget {
  const MySessionsScreen({super.key});

  @override
  ConsumerState<MySessionsScreen> createState() => _MySessionsScreenState();
}

class _MySessionsScreenState extends ConsumerState<MySessionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Subject? _subjectFilter;
  DateTimeRange? _dateRange;
  String? _dateRangeLabel;

  static const _indicatorColor = Color(0xFF5186CD);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SearchBottomSheet(),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: AppColors.accent),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _dateRange = range;
        String fmt(DateTime d) => '${d.month}/${d.day}';
        _dateRangeLabel = '${fmt(range.start)} – ${fmt(range.end)}';
      });
    }
  }

  List<Session> _applyFilters(List<Session> src) {
    var list = src;
    if (_subjectFilter != null) {
      list = list.where((s) => s.subject == _subjectFilter).toList();
    }
    if (_dateRange != null) {
      list = list.where((s) {
        final d = s.startTime;
        return !d.isBefore(_dateRange!.start) && !d.isAfter(_dateRange!.end);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).asData?.value;

    // When the user is not yet loaded, show an empty shell with 0 counts.
    if (me == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(
          upcomingCount: 0,
          completedCount: 0,
          mineCount: 0,
          subjects: const [],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Watch both providers once — split memberships in-memory.
    final membershipsAsync = ref.watch(myMembershipsProvider(me.id));
    final hostedAsync = ref.watch(hostedSessionsProvider(me.id));
    // CHANGED: also watch pending join requests for Upcoming tab
    final pendingAsync = ref.watch(myPendingSessionsProvider(me.id));

    final memberships = membershipsAsync.asData?.value ?? [];
    final hosted = hostedAsync.asData?.value ?? [];
    final firestorePending = pendingAsync.asData?.value ?? [];
    final localPending = ref.watch(localPendingSessionsProvider);
    // Local (optimistic) entries override Firestore entries on the same ID so
    // the Upcoming tab populates instantly after a join request.
    final pendingById = <String, Session>{
      for (final s in firestorePending) s.id: s,
      for (final s in localPending) s.id: s,
    };
    final pending = pendingById.values.toList();

    final now = DateTime.now();
    // CHANGED: pending sessions appear first, then upcoming joined sessions
    final upcoming = _applyFilters([
      ...pending,
      ...memberships.where((s) => s.endTime.isAfter(now)),
    ]);
    final completed = _applyFilters(
      memberships.where((s) => !s.endTime.isAfter(now)).toList(),
    );
    final mine = _applyFilters(hosted);

    // Build subject list from present subjects across all streams.
    final subjects = {
      ...memberships.map((s) => s.subject),
      ...hosted.map((s) => s.subject),
      // CHANGED: include pending session subjects in filter chips
      ...pending.map((s) => s.subject),
    }.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(
        upcomingCount: upcoming.length,
        completedCount: completed.length,
        mineCount: mine.length,
        subjects: subjects,
      ),
      body: Column(
        children: [
          _FilterRow(
            subjects: subjects,
            activeSubject: _subjectFilter,
            dateRangeLabel: _dateRangeLabel,
            onSubjectTap: (s) =>
                setState(() => _subjectFilter = _subjectFilter == s ? null : s),
            onDateRangeTap: _pickDateRange,
            onClearDate: () => setState(() {
              _dateRange = null;
              _dateRangeLabel = null;
            }),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _tabContent(
                  async: membershipsAsync,
                  sessions: upcoming,
                  emptyIcon: Icons.upcoming_outlined,
                  emptyTitle: 'No upcoming sessions',
                  emptyBody: 'Sessions you join will appear here',
                  onCardTap: (s) =>
                      context.push('/my-sessions/member/${s.id}'),
                ),
                _tabContent(
                  async: membershipsAsync,
                  sessions: completed,
                  emptyIcon: Icons.check_circle_outline,
                  emptyTitle: 'No completed sessions yet',
                  emptyBody: 'Completed sessions will show up here',
                  onCardTap: (s) =>
                      context.push('/my-sessions/member/${s.id}'),
                ),
                _tabContent(
                  async: hostedAsync,
                  sessions: mine,
                  emptyIcon: Icons.add_circle_outline,
                  emptyTitle: 'No sessions created',
                  emptyBody: 'Tap + to create your first session!',
                  onCardTap: (s) => context.push('/my-sessions/${s.id}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the correct state (loading / error / data) for a single tab.
  Widget _tabContent({
    required AsyncValue<List<Session>> async,
    required List<Session> sessions,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyBody,
    void Function(Session)? onCardTap,
  }) {
    if (async.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (async.hasError) {
      return Center(
        child: Text(
          'Could not load sessions. Please try again.',
          style: TextStyle(color: AppColors.error),
          textAlign: TextAlign.center,
        ),
      );
    }
    return _SessionList(
      sessions: sessions,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptyBody: emptyBody,
      onCardTap: onCardTap,
    );
  }

  /// Builds an [AppBar] with a [TabBar] that shows live counts.
  PreferredSizeWidget _buildAppBar({
    required int upcomingCount,
    required int completedCount,
    required int mineCount,
    required List<Subject> subjects,
  }) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: const Text('My Sessions'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_outlined),
          onPressed: _openSearch,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: _indicatorColor,
        labelColor: _indicatorColor,
        unselectedLabelColor: AppColors.hint,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        tabs: [
          Tab(text: 'Upcoming ($upcomingCount)'),
          Tab(text: 'Completed ($completedCount)'),
          Tab(text: 'Mine ($mineCount)'),
        ],
      ),
    );
  }
}

// ── Filter row ─────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final List<Subject> subjects;
  final Subject? activeSubject;
  final String? dateRangeLabel;
  final ValueChanged<Subject> onSubjectTap;
  final VoidCallback onDateRangeTap;
  final VoidCallback onClearDate;

  const _FilterRow({
    required this.subjects,
    required this.activeSubject,
    required this.dateRangeLabel,
    required this.onSubjectTap,
    required this.onDateRangeTap,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Date range chip
            FilterChip(
              avatar: const Icon(Icons.date_range_outlined, size: 15),
              label: Text(dateRangeLabel ?? 'Date Range'),
              selected: dateRangeLabel != null,
              onSelected: (_) => onDateRangeTap(),
              selectedColor: AppColors.secondary,
              checkmarkColor: AppColors.accent,
              deleteIcon: dateRangeLabel != null
                  ? const Icon(Icons.close, size: 14)
                  : null,
              onDeleted: dateRangeLabel != null ? onClearDate : null,
              labelStyle: TextStyle(
                fontSize: 12,
                color: dateRangeLabel != null
                    ? AppColors.accent
                    : AppColors.hint,
              ),
              side: BorderSide(
                color: dateRangeLabel != null
                    ? AppColors.accent
                    : AppColors.border,
              ),
              backgroundColor: AppColors.surface,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            ...subjects.map((s) {
              final active = s == activeSubject;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(s.displayName),
                  selected: active,
                  onSelected: (_) => onSubjectTap(s),
                  selectedColor: AppColors.secondary,
                  checkmarkColor: AppColors.accent,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.accent : AppColors.hint,
                  ),
                  side: BorderSide(
                    color: active ? AppColors.accent : AppColors.border,
                  ),
                  backgroundColor: AppColors.surface,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Session list ───────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final List<Session> sessions;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final void Function(Session)? onCardTap;

  const _SessionList({
    required this.sessions,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (sessions.isEmpty) {
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
              child: Icon(emptyIcon, size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text(
              emptyTitle,
              style: tt.displaySmall?.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 6),
            Text(
              emptyBody,
              style: tt.bodyMedium?.copyWith(color: AppColors.hint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sessions.length,
      itemBuilder: (ctx, i) {
        final session = sessions[i];
        // CHANGED: pending cards stay interactive so Cancel button receives taps
        if (onCardTap != null && session.myStatus != JoinStatus.pending) {
          return GestureDetector(
            onTap: () => onCardTap!(session),
            child: AbsorbPointer(child: SessionCard(session: session)),
          );
        }
        return SessionCard(session: session);
      },
    );
  }
}
