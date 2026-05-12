import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1-on-1 DM conversation between two friends.
///
/// Firestore path: chats/{dmId}
/// dmId is deterministic: [uid1, uid2].sorted().join('_')
///
/// Unread counter is stored as a top-level field `unreadCount_{uid}` on the
/// Firestore doc (ADR 0014) but exposed here as [unreadCountForMe] for a
/// clean model API.
class DmConversation {
  final String id;
  final List<String> participantIds;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCountForMe;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DmConversation({
    required this.id,
    required this.participantIds,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.unreadCountForMe,
    required this.createdAt,
    this.updatedAt,
  });

  /// [myUid] is used to parse the `unreadCount_{uid}` field for the caller.
  factory DmConversation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('DmConversation ${doc.id} has no data');
    return DmConversation(
      id: doc.id,
      participantIds:
          List<String>.from(data['participantIds'] as List? ?? const []),
      lastMessageText: data['lastMessageText'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      unreadCountForMe: (data['unreadCount_$myUid'] as int?) ?? 0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Serialises the structural fields. Unread counter fields are written
  /// separately via FieldValue.increment — do not include them here.
  Map<String, dynamic> toFirestore() {
    return {
      'participantIds': participantIds,
      'lastMessageText': lastMessageText,
      'lastMessageAt':
          lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'lastMessageSenderId': lastMessageSenderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt':
          updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  DmConversation copyWith({
    List<String>? participantIds,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    int? unreadCountForMe,
    DateTime? updatedAt,
  }) {
    return DmConversation(
      id: id,
      participantIds: participantIds ?? this.participantIds,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCountForMe: unreadCountForMe ?? this.unreadCountForMe,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
