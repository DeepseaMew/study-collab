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
  });

  bool get isFull => participantCount >= capacity;
  int get spotsLeft => capacity - participantCount;
  bool get isPasswordProtected => visibility == SessionVisibility.private;
  bool get requiresApproval => joinApproval == JoinApproval.hostApproval;

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
    };
  }

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
    );
  }
}