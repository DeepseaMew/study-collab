import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';

class AppUser {
  final String id;
  final String email;
  final String username;
  final String bio;
  final String? profilePhotoUrl;
  final AcademicLevel academicLevel;
  final int studentYear;          
  final String faculty;           
  final int friendsCount;
  final int sessionsCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    this.bio = '',
    this.profilePhotoUrl,
    this.academicLevel = AcademicLevel.undergraduate,
    this.studentYear = 1,
    this.faculty = '',
    this.friendsCount = 0,
    this.sessionsCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Max year allowed based on academic level.
  /// Undergrad: 1–4, Postgrad: 1–2.
  static int maxYearFor(AcademicLevel level) =>
      level == AcademicLevel.postgraduate ? 2 : 4;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception('User document ${doc.id} has no data');
    return AppUser(
      id: doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      academicLevel: AcademicLevel.fromString(data['academicLevel'] as String?),
      studentYear: data['studentYear'] as int? ?? 1,
      faculty: data['faculty'] as String? ?? '',
      friendsCount: data['friendsCount'] as int? ?? 0,
      sessionsCount: data['sessionsCount'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Serialises the user for Firestore writes.
  ///
  /// NOTE: `createdAt` and `updatedAt` are intentionally excluded.
  /// Every write call-site in the services layer supplies these via
  /// `FieldValue.serverTimestamp()` so the timestamp is authoritative and
  /// consistent across clients.  Storing `Timestamp.fromDate(DateTime.now())`
  /// here would use a client-local clock, which violates the project rule.
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'username': username,
      'bio': bio,
      'profilePhotoUrl': profilePhotoUrl,
      'academicLevel': academicLevel.name,
      'studentYear': studentYear,
      'faculty': faculty,
      'friendsCount': friendsCount,
      'sessionsCount': sessionsCount,
    };
  }

  AppUser copyWith({
    String? email,
    String? username,
    String? bio,
    String? profilePhotoUrl,
    AcademicLevel? academicLevel,
    int? studentYear,
    String? faculty,
    int? friendsCount,
    int? sessionsCount,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id,
      email: email ?? this.email,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      academicLevel: academicLevel ?? this.academicLevel,
      studentYear: studentYear ?? this.studentYear,
      faculty: faculty ?? this.faculty,
      friendsCount: friendsCount ?? this.friendsCount,
      sessionsCount: sessionsCount ?? this.sessionsCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
