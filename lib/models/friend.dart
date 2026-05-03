import 'package:cloud_firestore/cloud_firestore.dart';

class Friend {
  final String friendUserId;
  final String ownerId;
  final String username;
  final String? profilePhotoUrl;
  final String? bio;
  final DateTime addedAt;

  const Friend({
    required this.friendUserId,
    required this.ownerId,
    required this.username,
    this.profilePhotoUrl,
    this.bio,
    required this.addedAt,
  });

  factory Friend.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String ownerId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('Friend document ${doc.id} has no data');
    return Friend(
      friendUserId: doc.id,
      ownerId: ownerId,
      username: data['username'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      bio: data['bio'] as String?,
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'profilePhotoUrl': profilePhotoUrl,
      'bio': bio,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }

  Friend copyWith({
    String? username,
    String? profilePhotoUrl,
    String? bio,
  }) {
    return Friend(
      friendUserId: friendUserId,
      ownerId: ownerId,
      username: username ?? this.username,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      bio: bio ?? this.bio,
      addedAt: addedAt,
    );
  }
}

enum FriendRequestStatus {
  pending,
  accepted,
  declined;

  static FriendRequestStatus fromString(String? value) {
    return FriendRequestStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => FriendRequestStatus.pending,
    );
  }
}

class FriendRequest {
  final String id;
  final String recipientId;
  final String senderId;
  final String senderUsername;
  final String? senderPhotoUrl;
  final FriendRequestStatus status;
  final DateTime sentAt;
  final DateTime? respondedAt;

  const FriendRequest({
    required this.id,
    required this.recipientId,
    required this.senderId,
    required this.senderUsername,
    this.senderPhotoUrl,
    this.status = FriendRequestStatus.pending,
    required this.sentAt,
    this.respondedAt,
  });

  bool get isPending => status == FriendRequestStatus.pending;

  factory FriendRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String recipientId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('FriendRequest document ${doc.id} has no data');
    return FriendRequest(
      id: doc.id,
      recipientId: recipientId,
      senderId: data['senderId'] as String? ?? '',
      senderUsername: data['senderUsername'] as String? ?? '',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      status: FriendRequestStatus.fromString(data['status'] as String?),
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderUsername': senderUsername,
      'senderPhotoUrl': senderPhotoUrl,
      'status': status.name,
      'sentAt': Timestamp.fromDate(sentAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
    };
  }

  FriendRequest copyWith({
    FriendRequestStatus? status,
    DateTime? respondedAt,
  }) {
    return FriendRequest(
      id: id,
      recipientId: recipientId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderPhotoUrl: senderPhotoUrl,
      status: status ?? this.status,
      sentAt: sentAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}