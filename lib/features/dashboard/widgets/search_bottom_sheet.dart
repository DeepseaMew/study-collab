import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/enums.dart';
import '../../../models/session.dart';
import '../providers/dashboard_providers.dart';
import 'session_card.dart';

class SearchBottomSheet extends ConsumerStatefulWidget {
  const SearchBottomSheet({super.key});

  @override
  ConsumerState<SearchBottomSheet> createState() =>
      _SearchBottomSheetState();
}

class _SearchBottomSheetState extends ConsumerState<SearchBottomSheet> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<Subject> _selectedSubjects = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Session> _filtered(List<Session> all) {
    var list = all;

    // Subject filter (multi-select — any selected subject matches)
    if (_selectedSubjects.isNotEmpty) {
      list =
          list.where((s) => _selectedSubjects.contains(s.subject)).toList();
    }

    // Text search across title, description, hashtags, host
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      if (q.startsWith('#')) {
        final tag = q.substring(1);
        list = list
            .where((s) => s.hashtags.any((h) => h.toLowerCase().contains(tag)))
            .toList();
      } else if (q.startsWith('@')) {
        final host = q.substring(1);
        list = list
            .where((s) => s.hostName.toLowerCase().contains(host))
            .toList();
      } else {
        list = list
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.subject.displayName.toLowerCase().contains(q) ||
                s.description.toLowerCase().contains(q) ||
                s.hostName.toLowerCase().contains(q) ||
                s.hashtags.any((h) => h.toLowerCase().contains(q)))
            .toList();
      }
    }

    return list;
  }

  void _toggleSubject(Subject subject) {
    setState(() {
      if (_selectedSubjects.contains(subject)) {
        _selectedSubjects.remove(subject);
      } else {
        _selectedSubjects.add(subject);
      }
    });
  }

  void _clearSubjects() => setState(() => _selectedSubjects.clear());

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final allSessions = ref.watch(dashboardSessionsProvider);

    // Derive sorted unique subjects from sessions present
    final subjects = allSessions.map((s) => s.subject).toSet().toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    final results = _filtered(allSessions);
    final hasActiveFilters =
        _selectedSubjects.isNotEmpty || _query.trim().isNotEmpty;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Text('Search Sessions', style: tt.displaySmall),
                  const Spacer(),
                  if (hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        _clearSubjects();
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      child: const Text(
                        'Clear all',
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 13),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.hint,
                  ),
                ],
              ),
            ),
            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search by title, #hashtag, @host...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            // Subject filter chips
            if (subjects.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Text(
                      'Filter by subject',
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.hint,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (_selectedSubjects.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearSubjects,
                        child: Text(
                          'Clear (${_selectedSubjects.length})',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: subjects.map((subject) {
                    final isSelected = _selectedSubjects.contains(subject);
                    return _SubjectChip(
                      label: subject.displayName,
                      color: subject.color,
                      selected: isSelected,
                      onTap: () => _toggleSubject(subject),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Divider(height: 1, color: AppColors.border),
            // Result count label
            if (hasActiveFilters)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${results.length} result${results.length != 1 ? 's' : ''}',
                      style:
                          tt.labelSmall?.copyWith(color: AppColors.hint),
                    ),
                  ],
                ),
              ),
            // Results
            Flexible(
              child: results.isEmpty
                  ? _NoResults(query: _query)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: results.length,
                      itemBuilder: (_, i) =>
                          SessionCard(session: results[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subject chip ─────────────────────────────────────────────────────────────

class _SubjectChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SubjectChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No results ───────────────────────────────────────────────────────────────

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppColors.disabled),
            const SizedBox(height: 16),
            Text(
              query.isEmpty ? 'Start typing to search' : 'No sessions found',
              style: tt.titleLarge?.copyWith(color: AppColors.hint),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Try a different keyword or subject',
                style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}