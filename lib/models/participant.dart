import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';

enum ParticipantRole {
  host,
  member;

  static ParticipantRole fromString(String? value) {
    return ParticipantRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => ParticipantRole.member,
    );
  }
}

/// A member of a session.
///
/// Stored at: sessions/{sessionId}/members/{userId}
/// Doc ID = userId (deterministic).
///
/// Card-render fields (ADR 0008) cached here so the "My Sessions" screen
/// can render cards without fetching the parent session doc:
///   sessionTitle, sessionStartTime, sessionEndTime, sessionStatus,
///   sessionSubject, hostId
///
/// These must be updated via WriteBatch whenever the host edits the session
/// (see session_service.editSession and cancelSession / postponeSession).
///
/// userId is also stored as a field (not just the doc ID) so that
/// collectionGroup queries on 'members' can filter by userId.
class Participant {
  final String userId;
  final String sessionId;
  final String username;
  final String? profilePhotoUrl;
  final ParticipantRole role;
  final DateTime joinedAt;
  final bool attended;

  // ── Card-render fields (ADR 0008) ─────────────────────────────────────────
  final String sessionTitle;
  final DateTime sessionStartTime;
  final DateTime sessionEndTime;
  final SessionStatus sessionStatus;
  final Subject sessionSubject;
  final String hostId;

  const Participant({
    required this.userId,
    required this.sessionId,
    required this.username,
    this.profilePhotoUrl,
    this.role = ParticipantRole.member,
    required this.joinedAt,
    this.attended = false,
    required this.sessionTitle,
    required this.sessionStartTime,
    required this.sessionEndTime,
    this.sessionStatus = SessionStatus.upcoming,
    this.sessionSubject = Subject.other,
    required this.hostId,
  });

  bool get isHost => role == ParticipantRole.host;

  factory Participant.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String sessionId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('Participant document ${doc.id} has no data');
    return Participant(
      userId: doc.id,
      sessionId: sessionId,
      username: data['username'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      role: ParticipantRole.fromString(data['role'] as String?),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attended: data['attended'] as bool? ?? false,
      sessionTitle: data['sessionTitle'] as String? ?? '',
      sessionStartTime:
          (data['sessionStartTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sessionEndTime:
          (data['sessionEndTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sessionStatus: SessionStatus.fromString(data['sessionStatus'] as String?),
      sessionSubject: Subject.fromString(data['sessionSubject'] as String?),
      hostId: data['hostId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      'profilePhotoUrl': profilePhotoUrl,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'attended': attended,
      'sessionTitle': sessionTitle,
      'sessionStartTime': Timestamp.fromDate(sessionStartTime),
      'sessionEndTime': Timestamp.fromDate(sessionEndTime),
      'sessionStatus': sessionStatus.name,
      'sessionSubject': sessionSubject.name,
      'hostId': hostId,
    };
  }

  Participant copyWith({
    String? username,
    String? profilePhotoUrl,
    ParticipantRole? role,
    bool? attended,
    String? sessionTitle,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
    SessionStatus? sessionStatus,
    Subject? sessionSubject,
    String? hostId,
  }) {
    return Participant(
      userId: userId,
      sessionId: sessionId,
      username: username ?? this.username,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      role: role ?? this.role,
      joinedAt: joinedAt,
      attended: attended ?? this.attended,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      sessionStartTime: sessionStartTime ?? this.sessionStartTime,
      sessionEndTime: sessionEndTime ?? this.sessionEndTime,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      sessionSubject: sessionSubject ?? this.sessionSubject,
      hostId: hostId ?? this.hostId,
    );
  }
}
