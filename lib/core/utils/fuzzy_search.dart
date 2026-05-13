// CHANGED: new file — pure-Dart fuzzy search utility.
// No Flutter or Firebase dependencies — only imports Session from models.
// Works entirely on the in-memory List<Session>.

import 'package:study_collab/models/session.dart';

// ── Match type ────────────────────────────────────────────────────────────────

enum MatchType {
  /// Query equals the target field exactly, or the target starts with the query.
  exact,

  /// Query is a substring of the target field.
  partial,

  /// All characters of the query appear in order inside the target field
  /// (subsequence match).
  fuzzy,
}

// ── Result ────────────────────────────────────────────────────────────────────

class SearchResult {
  final Session session;

  /// Relevance score in the range 0.0–1.0 (higher is better).
  final double score;

  final MatchType matchType;

  const SearchResult({
    required this.session,
    required this.score,
    required this.matchType,
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Fuzzy-searches [sessions] for [query] and returns ranked results.
///
/// Scoring rules (case-insensitive; applied to each searchable field):
///   1. Exact match on title OR subject.displayName → 1.0, MatchType.exact
///   2. Starts-with match on any field              → 0.9, MatchType.exact
///   3. Contains (substring) match on any field     → 0.8, MatchType.partial
///   4. Subsequence match on any field              →
///        0.3 + 0.5 * (matchedChars / target.length), MatchType.fuzzy
///
/// The BEST score across all fields is used for each session.
/// Results below 0.3 are discarded.
/// Output is sorted descending by score.
///
/// Special prefix handling:
///   `#query` → searches hashtags fields only (strips the `#`).
///   `@query` → searches hostName only (strips the `@`).
List<SearchResult> fuzzySearch(
  String query,
  List<Session> sessions, {
  double minScore = 0.3,
}) {
  final raw = query.trim();
  if (raw.isEmpty) return [];

  final results = <SearchResult>[];

  for (final session in sessions) {
    // CHANGED: resolve the fields to search based on special prefix
    final _FieldSet fieldSet;
    if (raw.startsWith('#')) {
      final tag = raw.substring(1).toLowerCase();
      if (tag.isEmpty) continue;
      fieldSet = _FieldSet.hashtags(session, tag);
    } else if (raw.startsWith('@')) {
      final host = raw.substring(1).toLowerCase();
      if (host.isEmpty) continue;
      fieldSet = _FieldSet.host(session, host);
    } else {
      fieldSet = _FieldSet.all(session, raw.toLowerCase());
    }

    final best = _bestScore(fieldSet);
    if (best == null || best.score < minScore) continue;
    results.add(
      SearchResult(
        session: session,
        score: best.score,
        matchType: best.matchType,
      ),
    );
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results;
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Holds the (normalised query, targets) pair for a single session.
class _FieldSet {
  final String query;
  final List<String> targets;

  /// Whether this is a hashtag-mode search (exact vs prefix vs substring
  /// against individual hashtag strings).
  final bool hashtagMode;

  const _FieldSet({
    required this.query,
    required this.targets,
    this.hashtagMode = false,
  });

  // CHANGED: factory constructors for each search mode
  factory _FieldSet.all(Session s, String q) {
    final hashtagsJoined = s.hashtags.join(' ');
    return _FieldSet(
      query: q,
      targets: [
        s.title.toLowerCase(),
        s.subject.displayName.toLowerCase(),
        s.description.toLowerCase(),
        s.hostName.toLowerCase(),
        hashtagsJoined.toLowerCase(),
      ],
    );
  }

  factory _FieldSet.hashtags(Session s, String q) {
    return _FieldSet(
      query: q,
      targets: s.hashtags.map((h) => h.toLowerCase()).toList(),
      hashtagMode: true,
    );
  }

  factory _FieldSet.host(Session s, String q) {
    return _FieldSet(query: q, targets: [s.hostName.toLowerCase()]);
  }
}

/// Score a single (query, target) pair.
/// Returns null when the score is 0 (no match).
({double score, MatchType matchType})? _scoreField(
  String q,
  String target,
  bool isTitle,
  bool isSubject,
) {
  if (target.isEmpty) return null;

  // Rule 1 — exact match on title or subject.displayName only
  if ((isTitle || isSubject) && target == q) {
    return (score: 1.0, matchType: MatchType.exact);
  }

  // Rule 2 — starts-with on any field
  if (target.startsWith(q)) {
    return (score: 0.9, matchType: MatchType.exact);
  }

  // Rule 3 — substring (contains)
  if (target.contains(q)) {
    return (score: 0.8, matchType: MatchType.partial);
  }

  // Rule 4 — subsequence
  final matchedChars = _subsequenceMatchCount(q, target);
  if (matchedChars == q.length) {
    final subScore = 0.3 + 0.5 * (matchedChars / target.length);
    return (score: subScore, matchType: MatchType.fuzzy);
  }

  return null;
}

/// Returns the best ({score, matchType}) across all targets in [fieldSet],
/// or null if nothing matched.
({double score, MatchType matchType})? _bestScore(_FieldSet fieldSet) {
  ({double score, MatchType matchType})? best;

  for (var i = 0; i < fieldSet.targets.length; i++) {
    final target = fieldSet.targets[i];

    // In hashtag mode each target is an individual hashtag string, not the
    // joined blob — treat none of them as title/subject for the exact rule.
    final isTitle = !fieldSet.hashtagMode && i == 0;
    final isSubject = !fieldSet.hashtagMode && i == 1;

    final candidate = _scoreField(fieldSet.query, target, isTitle, isSubject);
    if (candidate == null) continue;
    if (best == null || candidate.score > best.score) {
      best = candidate;
    }
  }

  return best;
}

/// Counts how many characters of [query] appear (in order) inside [target].
/// Returns [query.length] when all chars are found (full subsequence match).
int _subsequenceMatchCount(String query, String target) {
  var qi = 0;
  for (var ti = 0; ti < target.length && qi < query.length; ti++) {
    if (target[ti] == query[qi]) qi++;
  }
  return qi;
}
