enum Subject {
  mathematics,
  computerScience,
  chemistry,
  physics,
  biology,
  economics,
  english,
  other;

  String get displayName {
    switch (this) {
      case Subject.mathematics:     return 'Mathematics';
      case Subject.computerScience: return 'Computer Science';
      case Subject.chemistry:       return 'Chemistry';
      case Subject.physics:         return 'Physics';
      case Subject.biology:         return 'Biology';
      case Subject.economics:       return 'Economics';
      case Subject.english:         return 'English';
      case Subject.other:           return 'Other';
    }
  }

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

enum SessionVisibility {
  public,
  private;

  static SessionVisibility fromString(String? value) {
    return SessionVisibility.values.firstWhere(
      (v) => v.name == value,
      orElse: () => SessionVisibility.public,
    );
  }
}

enum JoinApproval {
  none,
  hostApproval;

  static JoinApproval fromString(String? value) {
    return JoinApproval.values.firstWhere(
      (a) => a.name == value,
      orElse: () => JoinApproval.none,
    );
  }
}
