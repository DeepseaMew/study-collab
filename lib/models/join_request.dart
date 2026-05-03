import 'package:cloud_firestore/cloud_firestore.dart';

enum JoinRequestStatus {
  pending,
  approved,
  declined;

  static JoinRequestStatus fromString(String? value) {
    return JoinRequestStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => JoinRequestStatus.pending,
    );
  }
}

class JoinRequest {
  final String id;
  final String sessionId;
  final String userId;
  final String username;
  final String? profilePhotoUrl;
  final JoinRequestStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;

  const JoinRequest({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.username,
    this.profilePhotoUrl,
    this.status = JoinRequestStatus.pending,
    required this.requestedAt,
    this.respondedAt,
  });

  bool get isPending  => status == JoinRequestStatus.pending;
  bool get isApproved => status == JoinRequestStatus.approved;
  bool get isDeclined => status == JoinRequestStatus.declined;

  factory JoinRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String sessionId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('JoinRequest document ${doc.id} has no data');
    return JoinRequest(
      id: doc.id,
      sessionId: sessionId,
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      status: JoinRequestStatus.fromString(data['status'] as String?),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      'profilePhotoUrl': profilePhotoUrl,
      'status': status.name,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
    };
  }

  JoinRequest copyWith({
    JoinRequestStatus? status,
    DateTime? respondedAt,
  }) {
    return JoinRequest(
      id: id,
      sessionId: sessionId,
      userId: userId,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
      status: status ?? this.status,
      requestedAt: requestedAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}