import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';

class Session {
  final String id;
  final String title;
  final Subject subject;
  final String description;
  final SessionVisibility visibility;
  final JoinApproval joinApproval;
  final String hostId;
  final String hostName;
  final String? hostPhotoUrl;
  final DateTime startTime;
  final DateTime endTime;
  final String location;
  final int capacity;
  final int participantCount;
  final SessionStatus status;
  final bool reviewsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? passwordHash;
  final int? studentYear;
  final AcademicLevel? academicLevel;
  final List<String> hashtags;

  /// Current user's relationship to this session.
  /// Transient — NOT stored in Firestore. Computed by services when loading
  /// sessions (e.g. dashboard checks participants + join_requests for the
  /// current user). Defaults to notJoined when unknown.
  final JoinStatus myStatus;

  const Session({
    required this.id,
    required this.title,
    required this.subject,
    this.description = '',
    this.visibility = SessionVisibility.public,
    this.joinApproval = JoinApproval.none,
    required this.hostId,
    required this.hostName,
    this.hostPhotoUrl,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.capacity,
    this.participantCount = 0,
    this.status = SessionStatus.upcoming,
    this.reviewsEnabled = true,
    required this.createdAt,
    required this.updatedAt,
    this.passwordHash,
    this.studentYear,
    this.academicLevel,
    this.hashtags = const [],
    this.myStatus = JoinStatus.notJoined,
  });

  bool get isFull => participantCount >= capacity;
  int get spotsLeft => capacity - participantCount;
  bool get isPasswordProtected =>
      passwordHash != null && passwordHash!.isNotEmpty;
  bool get requiresApproval =>
      visibility == SessionVisibility.approval ||
      joinApproval == JoinApproval.hostApproval;

  factory Session.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception('Session document ${doc.id} has no data');
    return Session(
      id: doc.id,
      title: data['title'] as String? ?? '',
      subject: Subject.fromString(data['subject'] as String?),
      description: data['description'] as String? ?? '',
      visibility: SessionVisibility.fromString(data['visibility'] as String?),
      joinApproval: JoinApproval.fromString(data['joinApproval'] as String?),
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      hostPhotoUrl: data['hostPhotoUrl'] as String?,
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'] as String? ?? '',
      capacity: data['capacity'] as int? ?? 0,
      participantCount: data['participantCount'] as int? ?? 0,
      status: SessionStatus.fromString(data['status'] as String?),
      reviewsEnabled: data['reviewsEnabled'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      passwordHash: data['passwordHash'] as String?,
      studentYear: (data['studentYear'] as num?)?.toInt(),
      academicLevel: data['academicLevel'] == null
          ? null
          : AcademicLevel.fromString(data['academicLevel'] as String?),
      hashtags: (data['hashtags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      // myStatus is transient — never read from Firestore. Computed by services.
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'subject': subject.name,
      'description': description,
      'visibility': visibility.name,
      'joinApproval': joinApproval.name,
      'hostId': hostId,
      'hostName': hostName,
      'hostPhotoUrl': hostPhotoUrl,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'location': location,
      'capacity': capacity,
      'participantCount': participantCount,
      'status': status.name,
      'reviewsEnabled': reviewsEnabled,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (passwordHash != null) 'passwordHash': passwordHash!, // ignore: use_null_aware_elements
      if (studentYear != null) 'studentYear': studentYear!, // ignore: use_null_aware_elements
      if (academicLevel != null) 'academicLevel': academicLevel!.name,
      'hashtags': hashtags,
      // myStatus is intentionally NOT written — it's a per-user computed value.
    };
  }

  static const Object _sentinel = Object();

  Session copyWith({
    String? title,
    Subject? subject,
    String? description,
    SessionVisibility? visibility,
    JoinApproval? joinApproval,
    String? hostName,
    String? hostPhotoUrl,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    int? capacity,
    int? participantCount,
    SessionStatus? status,
    bool? reviewsEnabled,
    DateTime? updatedAt,
    Object? passwordHash = _sentinel,
    Object? studentYear = _sentinel,
    Object? academicLevel = _sentinel,
    List<String>? hashtags,
    JoinStatus? myStatus,
  }) {
    return Session(
      id: id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      joinApproval: joinApproval ?? this.joinApproval,
      hostId: hostId,
      hostName: hostName ?? this.hostName,
      hostPhotoUrl: hostPhotoUrl ?? this.hostPhotoUrl,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      capacity: capacity ?? this.capacity,
      participantCount: participantCount ?? this.participantCount,
      status: status ?? this.status,
      reviewsEnabled: reviewsEnabled ?? this.reviewsEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      passwordHash: identical(passwordHash, _sentinel)
          ? this.passwordHash
          : passwordHash as String?,
      studentYear: identical(studentYear, _sentinel)
          ? this.studentYear
          : studentYear as int?,
      academicLevel: identical(academicLevel, _sentinel)
          ? this.academicLevel
          : academicLevel as AcademicLevel?,
      hashtags: hashtags ?? this.hashtags,
      myStatus: myStatus ?? this.myStatus,
    );
  }
}