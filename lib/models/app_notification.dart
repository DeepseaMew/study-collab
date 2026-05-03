import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  joinRequest,
  requestApproved,
  requestDeclined,
  newMessage,
  sessionReminder,
  sessionCancelled,
  friendRequest,
  unknown;

  static NotificationType fromString(String? value) {
    return NotificationType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => NotificationType.unknown,
    );
  }
}

class AppNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final String? sessionId;
  final String? sessionTitle;
  final String? chatId;
  final String? fromUserId;
  final String? fromUsername;
  final String? fromUserPhotoUrl;
  final String? body;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    this.sessionId,
    this.sessionTitle,
    this.chatId,
    this.fromUserId,
    this.fromUsername,
    this.fromUserPhotoUrl,
    this.body,
    this.read = false,
    required this.createdAt,
  });

  bool get isUnread => !read;

  String get title {
    switch (type) {
      case NotificationType.joinRequest:
        return '${fromUsername ?? "Someone"} wants to join';
      case NotificationType.requestApproved:
        return 'Your request was approved!';
      case NotificationType.requestDeclined:
        return 'Your request was declined';
      case NotificationType.newMessage:
        return '${fromUsername ?? "Someone"} sent you a message';
      case NotificationType.sessionReminder:
        return '${sessionTitle ?? "Your session"} starts soon';
      case NotificationType.sessionCancelled:
        return '${sessionTitle ?? "A session"} was cancelled';
      case NotificationType.friendRequest:
        return '${fromUsername ?? "Someone"} sent you a friend request';
      case NotificationType.unknown:
        return 'Notification';
    }
  }

  String? get subtitle {
    switch (type) {
      case NotificationType.joinRequest:
      case NotificationType.requestApproved:
      case NotificationType.requestDeclined:
      case NotificationType.sessionReminder:
      case NotificationType.sessionCancelled:
        return sessionTitle;
      case NotificationType.newMessage:
        return body;
      default:
        return null;
    }
  }

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String userId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('Notification document ${doc.id} has no data');
    return AppNotification(
      id: doc.id,
      userId: userId,
      type: NotificationType.fromString(data['type'] as String?),
      sessionId: data['sessionId'] as String?,
      sessionTitle: data['sessionTitle'] as String?,
      chatId: data['chatId'] as String?,
      fromUserId: data['fromUserId'] as String?,
      fromUsername: data['fromUsername'] as String?,
      fromUserPhotoUrl: data['fromUserPhotoUrl'] as String?,
      body: data['body'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'sessionId': sessionId,
      'sessionTitle': sessionTitle,
      'chatId': chatId,
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'fromUserPhotoUrl': fromUserPhotoUrl,
      'body': body,
      'read': read,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      chatId: chatId,
      fromUserId: fromUserId,
      fromUsername: fromUsername,
      fromUserPhotoUrl: fromUserPhotoUrl,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}