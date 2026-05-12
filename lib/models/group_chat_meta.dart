import 'package:cloud_firestore/cloud_firestore.dart';

/// Metadata singleton for a session's group chat.
///
/// Firestore path: sessions/{sessionId}/groupChat/meta
///
/// Unread counters are stored in a map field `unreadCounts: {uid: int}` on
/// the Firestore doc (ADR 0014). Updated via dot-notation field paths so
/// other members' counters are not overwritten.
/// Exposed here as [unreadCountForMe] for a clean model API.
class GroupChatMeta {
  final String sessionId;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCountForMe;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GroupChatMeta({
    required this.sessionId,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.unreadCountForMe,
    required this.createdAt,
    this.updatedAt,
  });

  /// [myUid] is used to extract the caller's unread count from the map.
  factory GroupChatMeta.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String sessionId,
    String myUid,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('GroupChatMeta ${doc.id} has no data');
    final unreadCounts =
        (data['unreadCounts'] as Map<String, dynamic>?) ?? const {};
    return GroupChatMeta(
      sessionId: sessionId,
      lastMessageText: data['lastMessageText'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      unreadCountForMe: (unreadCounts[myUid] as int?) ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Serialises structural fields. Unread counter map is written separately
  /// via dot-notation field paths — do not include it here.
  Map<String, dynamic> toFirestore() {
    return {
      'lastMessageText': lastMessageText,
      'lastMessageAt':
          lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'lastMessageSenderId': lastMessageSenderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt':
          updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  GroupChatMeta copyWith({
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    int? unreadCountForMe,
    DateTime? updatedAt,
  }) {
    return GroupChatMeta(
      sessionId: sessionId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCountForMe: unreadCountForMe ?? this.unreadCountForMe,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
