// CHANGED: full rewrite — added recognition cues (H#6) and live fuzzy
// suggestions (H#7). See fuzzy_search.dart for the scoring logic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fuzzy_search.dart';
import '../../../models/enums.dart';
import '../../../models/session.dart';
import '../providers/dashboard_providers.dart';
import 'session_card.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kRecentSearchesKey = 'recent_searches';
const _kMaxStoredSearches = 10;
const _kMaxDisplayedRecentSearches = 5;
const _kMaxSuggestions = 3;
const _kMaxTrendingTags = 3;

// ── Main widget ───────────────────────────────────────────────────────────────

class SearchBottomSheet extends ConsumerStatefulWidget {
  const SearchBottomSheet({super.key});

  @override
  ConsumerState<SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends ConsumerState<SearchBottomSheet> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<Subject> _selectedSubjects = {};

  // CHANGED: recent searches loaded from SharedPreferences on initState
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  // CHANGED: async load from SharedPreferences
  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kRecentSearchesKey) ?? [];
    if (mounted) {
      setState(() {
        _recentSearches = stored.take(_kMaxDisplayedRecentSearches).toList();
      });
    }
  }

  // CHANGED: persist a search term; deduplicates and caps at 10 stored entries
  Future<void> _saveRecentSearch(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentSearchesKey) ?? [];
    list.remove(trimmed);
    list.insert(0, trimmed);
    final capped = list.take(_kMaxStoredSearches).toList();
    await prefs.setStringList(_kRecentSearchesKey, capped);
    if (mounted) {
      setState(() {
        _recentSearches = capped.take(_kMaxDisplayedRecentSearches).toList();
      });
    }
  }

  // CHANGED: clears all recent searches from prefs and local state
  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentSearchesKey);
    if (mounted) setState(() => _recentSearches = []);
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

  // CHANGED: compute top-N hashtags by frequency across all sessions
  List<String> _topHashtags(List<Session> sessions, {int limit = 3}) {
    final freq = <String, int>{};
    for (final s in sessions) {
      for (final tag in s.hashtags) {
        final normalised = tag.toLowerCase();
        freq[normalised] = (freq[normalised] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  // CHANGED: compute live suggestion strings from titles + subject display names
  List<String> _liveSuggestions(String query, List<Session> sessions) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final seen = <String>{};
    final suggestions = <String>[];

    for (final s in sessions) {
      for (final candidate in [s.title, s.subject.displayName]) {
        final lower = candidate.toLowerCase();
        if ((lower.startsWith(q) || lower.contains(q)) && seen.add(candidate)) {
          suggestions.add(candidate);
          if (suggestions.length >= _kMaxSuggestions) return suggestions;
        }
      }
    }
    return suggestions;
  }

  // CHANGED: highlight [query] inside [text] using RichText
  Widget _highlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.trim().toLowerCase();
    if (q.isEmpty || !lower.contains(q)) {
      return Text(
        text,
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      );
    }
    final start = lower.indexOf(q);
    final end = start + q.length;
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (start > 0)
            TextSpan(
              text: text.substring(0, start),
              style: const TextStyle(color: AppColors.text, fontSize: 14),
            ),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              color: Color(0xFF5186CD),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (end < text.length)
            TextSpan(
              text: text.substring(end),
              style: const TextStyle(color: AppColors.text, fontSize: 14),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final allSessions =
        ref.watch(dashboardSessionsProvider).asData?.value ?? [];

    // Derive sorted unique subjects from sessions present
    final subjects = allSessions.map((s) => s.subject).toSet().toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    // CHANGED: fuzzy-search pool respects the subject pre-filter
    final pool = _selectedSubjects.isEmpty
        ? allSessions
        : allSessions
              .where((s) => _selectedSubjects.contains(s.subject))
              .toList();

    final trimmedQuery = _query.trim();
    final isSearching = trimmedQuery.isNotEmpty;

    // CHANGED: use fuzzySearch when a query is present
    final fuzzyResults = isSearching
        ? fuzzySearch(trimmedQuery, pool)
        : <SearchResult>[];

    final hasActiveFilters = _selectedSubjects.isNotEmpty || isSearching;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                        style: TextStyle(color: AppColors.accent, fontSize: 13),
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
            // CHANGED: updated hint text to mention subject
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (v) => _saveRecentSearch(v),
                decoration: const InputDecoration(
                  hintText: 'Search by title, subject, #hashtag, @host...',
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
            // CHANGED: result count uses fuzzyResults.length when searching
            if (hasActiveFilters)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      isSearching
                          ? '${fuzzyResults.length} result${fuzzyResults.length != 1 ? 's' : ''}'
                          : '${pool.length} result${pool.length != 1 ? 's' : ''}',
                      style: tt.labelSmall?.copyWith(color: AppColors.hint),
                    ),
                  ],
                ),
              ),
            // Body: recognition cues OR fuzzy results
            Flexible(
              child: isSearching
                  ? _buildSearchResults(
                      context,
                      tt,
                      trimmedQuery,
                      fuzzyResults,
                      allSessions,
                      subjects,
                    )
                  : _buildRecognitionCues(context, tt, allSessions, subjects),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recognition cues (H#6) — shown when query is empty ─────────────────────

  // CHANGED: recognition cues section — recent searches, popular subjects,
  // trending tags
  Widget _buildRecognitionCues(
    BuildContext context,
    TextTheme tt,
    List<Session> allSessions,
    List<Subject> subjects,
  ) {
    final trendingTags = _topHashtags(allSessions, limit: _kMaxTrendingTags);
    final hasCues =
        _recentSearches.isNotEmpty ||
        subjects.isNotEmpty ||
        trendingTags.isNotEmpty;

    if (!hasCues) {
      return _EmptyHint(tt: tt);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Section A — recent searches
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  'RECENT SEARCHES',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.hint,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearRecentSearches,
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._recentSearches.map(
            (term) => ListTile(
              dense: true,
              leading: const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.hint,
              ),
              title: Text(
                term,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
              ),
              trailing: const Icon(
                Icons.north_west_rounded,
                size: 14,
                color: AppColors.hint,
              ),
              onTap: () {
                _controller.text = term;
                setState(() => _query = term);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Section B — popular subjects
        if (subjects.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'POPULAR SUBJECTS',
              style: tt.labelSmall?.copyWith(
                color: AppColors.hint,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subjects.map((subject) {
                return GestureDetector(
                  onTap: () {
                    _controller.text = subject.displayName;
                    setState(() => _query = subject.displayName);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subject.displayName,
                      style: const TextStyle(
                        color: Color(0xFF3d6fb7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Section C — trending tags
        if (trendingTags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'TRENDING TAGS',
              style: tt.labelSmall?.copyWith(
                color: AppColors.hint,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trendingTags.map((tag) {
                return GestureDetector(
                  onTap: () {
                    final query = '#$tag';
                    _controller.text = query;
                    setState(() => _query = query);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(
                        color: AppColors.hint,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // ── Search results with live suggestions (H#7) ──────────────────────────────

  // CHANGED: shows live suggestions row above fuzzy results
  Widget _buildSearchResults(
    BuildContext context,
    TextTheme tt,
    String query,
    List<SearchResult> fuzzyResults,
    List<Session> allSessions,
    List<Subject> subjects,
  ) {
    final suggestions = _liveSuggestions(query, allSessions);

    if (fuzzyResults.isEmpty) {
      return _buildNoResults(context, tt, query, allSessions, subjects);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // CHANGED: live suggestions row
        if (suggestions.isNotEmpty) ...[
          ...suggestions.map(
            (suggestion) => ListTile(
              dense: true,
              leading: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.hint,
              ),
              title: _highlightedText(suggestion, query),
              trailing: const Icon(
                Icons.north_west_rounded,
                size: 14,
                color: AppColors.hint,
              ),
              onTap: () {
                _controller.text = suggestion;
                setState(() => _query = suggestion);
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
        // CHANGED: session cards with match-type badge overlay
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: fuzzyResults.map((result) {
              return GestureDetector(
                onTap: () => _saveRecentSearch(query),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SessionCard(session: result.session),
                    // CHANGED: match-type badge — exact or fuzzy only
                    if (result.matchType != MatchType.partial)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _MatchBadge(matchType: result.matchType),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // CHANGED: no-results state with "did you mean?" and popular subjects pivot
  Widget _buildNoResults(
    BuildContext context,
    TextTheme tt,
    String query,
    List<Session> allSessions,
    List<Subject> subjects,
  ) {
    // Find best candidate across ALL sessions with threshold 0.0
    final allCandidates = fuzzySearch(query, allSessions, minScore: 0.0);
    final topCandidate = allCandidates.isNotEmpty ? allCandidates.first : null;
    final showDidYouMean = topCandidate != null && topCandidate.score > 0.3;

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(
          Icons.search_off_rounded,
          size: 56,
          color: AppColors.disabled,
        ),
        const SizedBox(height: 16),
        Text(
          'No exact match for "$query"',
          style: tt.titleLarge?.copyWith(color: AppColors.hint),
          textAlign: TextAlign.center,
        ),
        // CHANGED: "Did you mean?" suggestion
        if (showDidYouMean) ...[
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(
              Icons.lightbulb_outline_rounded,
              size: 20,
              color: AppColors.hint,
            ),
            title: Text(
              topCandidate.session.title,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
            ),
            subtitle: const Text(
              'Did you mean?',
              style: TextStyle(color: AppColors.hint, fontSize: 12),
            ),
            onTap: () {
              _controller.text = topCandidate.session.title;
              setState(() => _query = topCandidate.session.title);
            },
          ),
        ],
        // CHANGED: popular subjects pivot so user can change direction
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'POPULAR SUBJECTS',
            style: tt.labelSmall?.copyWith(
              color: AppColors.hint,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: subjects.map((subject) {
              return GestureDetector(
                onTap: () {
                  _controller.text = subject.displayName;
                  setState(() => _query = subject.displayName);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subject.displayName,
                    style: const TextStyle(
                      color: Color(0xFF3d6fb7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

// ── Subject chip (unchanged) ──────────────────────────────────────────────────

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

// ── Match-type badge (CHANGED: new) ───────────────────────────────────────────

// CHANGED: small overlay badge indicating how well the result matched
class _MatchBadge extends StatelessWidget {
  final MatchType matchType;
  const _MatchBadge({required this.matchType});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (matchType) {
      MatchType.exact => (
        'exact',
        AppColors.secondary,
        const Color(0xFF3d6fb7),
      ),
      MatchType.fuzzy => (
        'fuzzy',
        const Color(0xFFEAF3DE),
        const Color(0xFF3b6d11),
      ),
      MatchType.partial => ('', Colors.transparent, Colors.transparent),
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Empty hint (shown when no sessions at all) ────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final TextTheme tt;
  const _EmptyHint({required this.tt});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_rounded,
              size: 56,
              color: AppColors.disabled,
            ),
            const SizedBox(height: 16),
            Text(
              'Start typing to search',
              style: tt.titleLarge?.copyWith(color: AppColors.hint),
            ),
          ],
        ),
      ),
    );
  }
}
