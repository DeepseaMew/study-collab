import 'package:cloud_firestore/cloud_firestore.dart';

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

class Participant {
  final String userId;
  final String sessionId;
  final String username;
  final String? profilePhotoUrl;
  final ParticipantRole role;
  final DateTime joinedAt;
  final bool attended;

  const Participant({
    required this.userId,
    required this.sessionId,
    required this.username,
    this.profilePhotoUrl,
    this.role = ParticipantRole.member,
    required this.joinedAt,
    this.attended = false,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'profilePhotoUrl': profilePhotoUrl,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'attended': attended,
    };
  }

  Participant copyWith({
    String? username,
    String? profilePhotoUrl,
    ParticipantRole? role,
    bool? attended,
  }) {
    return Participant(
      userId: userId,
      sessionId: sessionId,
      username: username ?? this.username,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      role: role ?? this.role,
      joinedAt: joinedAt,
      attended: attended ?? this.attended,
    );
  }
}