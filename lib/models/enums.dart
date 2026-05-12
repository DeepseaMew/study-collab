import 'package:flutter/material.dart';

/// Academic subjects — each carries its own display color so the UI doesn't
/// need a separate color map. Use `subject.color` in widgets.
enum Subject {
  computerScience(Color(0xFF5186CD), 'Computer Science'),
  mathematics(Color(0xFFE67E22), 'Mathematics'),
  physics(Color(0xFFE74C3C), 'Physics'),
  chemistry(Color(0xFF27AE60), 'Chemistry'),
  biology(Color(0xFF16A085), 'Biology'),
  literature(Color(0xFF8E44AD), 'Literature'),
  english(Color(0xFF3498DB), 'English'),
  economics(Color(0xFF16A085), 'Economics'),
  other(Color(0xFF7F8C8D), 'Other');

  final Color color;
  final String displayName;

  const Subject(this.color, this.displayName);

  static Subject fromString(String? value) {
    return Subject.values.firstWhere(
      (s) => s.name == value,
      orElse: () => Subject.other,
    );
  }
}

enum AcademicLevel {
  undergraduate,
  postgraduate;

  String get displayName {
    switch (this) {
      case AcademicLevel.undergraduate: return 'Undergraduate';
      case AcademicLevel.postgraduate:  return 'Postgraduate';
    }
  }

  static AcademicLevel fromString(String? value) {
    return AcademicLevel.values.firstWhere(
      (l) => l.name == value,
      orElse: () => AcademicLevel.undergraduate,
    );
  }
}

enum SessionStatus {
  upcoming,
  ongoing,
  completed,
  cancelled;

  static SessionStatus fromString(String? value) {
    return SessionStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SessionStatus.upcoming,
    );
  }
}

/// Session visibility:
/// - public: visible in browse/search; joining requires host approval.
/// - private: hidden from browse/search; joinable only via password
///   (or a shared link that includes the session id).
enum SessionVisibility {
  public,
  private;

  /// Legacy values 'approval' (now folded into public) and any other
  /// unknown string fall back to public — public sessions still require
  /// host approval, so this is the safe default for old data.
  static SessionVisibility fromString(String? value) {
    if (value == 'private') return SessionVisibility.private;
    return SessionVisibility.public;
  }
}

/// Current user's relationship to a session.
/// This is a transient/computed value — NOT stored in Firestore.
/// Computed when loading sessions by checking host_id + participants + join_requests.
enum JoinStatus {
  notJoined,
  pending,
  joined,
  host;
}