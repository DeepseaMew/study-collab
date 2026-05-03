import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatType {
  direct,
  group;

  static ChatType fromString(String? value) {
    return ChatType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ChatType.direct,
    );
  }
}

class Chat {
  final String id;
  final ChatType type;
  final String? sessionId;
  final String displayName;
  final String? displayPhotoUrl;
  final List<String> participantIds;
  final Map<String, Map<String, dynamic>> participantInfo;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final Map<String, int> unreadCounts;
  final DateTime createdAt;

  const Chat({
    required this.id,
    required this.type,
    this.sessionId,
    required this.displayName,
    this.displayPhotoUrl,
    required this.participantIds,
    this.participantInfo = const {},
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastMessageSenderId,
    this.unreadCounts = const {},
    required this.createdAt,
  });

  bool get isDirect => type == ChatType.direct;
  bool get isGroup  => type == ChatType.group;

  int unreadCountFor(String userId) => unreadCounts[userId] ?? 0;

  String? otherUserId(String myUserId) {
    if (!isDirect) return null;
    return participantIds.firstWhere(
      (id) => id != myUserId,
      orElse: () => '',
    );
  }

  factory Chat.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception('Chat document ${doc.id} has no data');

    final rawInfo = data['participantInfo'] as Map<String, dynamic>? ?? {};
    final participantInfo = <String, Map<String, dynamic>>{};
    rawInfo.forEach((key, value) {
      if (value is Map<String, dynamic>) participantInfo[key] = value;
    });

    final rawUnread = data['unreadCounts'] as Map<String, dynamic>? ?? {};
    final unreadCounts = <String, int>{};
    rawUnread.forEach((key, value) {
      if (value is int) unreadCounts[key] = value;
    });

    return Chat(
      id: doc.id,
      type: ChatType.fromString(data['type'] as String?),
      sessionId: data['sessionId'] as String?,
      displayName: data['displayName'] as String? ?? '',
      displayPhotoUrl: data['displayPhotoUrl'] as String?,
      participantIds: List<String>.from(data['participantIds'] as List? ?? []),
      participantInfo: participantInfo,
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      unreadCounts: unreadCounts,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'sessionId': sessionId,
      'displayName': displayName,
      'displayPhotoUrl': displayPhotoUrl,
      'participantIds': participantIds,
      'participantInfo': participantInfo,
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCounts': unreadCounts,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Chat copyWith({
    String? displayName,
    String? displayPhotoUrl,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    Map<String, int>? unreadCounts,
  }) {
    return Chat(
      id: id,
      type: type,
      sessionId: sessionId,
      displayName: displayName ?? this.displayName,
      displayPhotoUrl: displayPhotoUrl ?? this.displayPhotoUrl,
      participantIds: participantIds,
      participantInfo: participantInfo,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      createdAt: createdAt,
    );
  }
}