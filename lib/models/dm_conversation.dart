import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1-on-1 DM conversation between two friends.
///
/// Firestore path: chats/{dmId}
/// dmId is deterministic: [uid1, uid2].sorted().join('_')
///
/// Unread counter is stored as a top-level field `unreadCount_{uid}` on the
/// Firestore doc (ADR 0014) but exposed here as [unreadCountForMe] for a
/// clean model API.
///
/// [otherUserName] and [otherUserPhotoUrl] are denormalized from the other
/// participant's user doc at conversation-creation time (getOrCreateDm).
/// They are NOT updated on profile changes in v1 — see chat_service.dart TODO.
class DmConversation {
  final String id;
  final List<String> participantIds;
  final String otherUserName;
  final String otherUserPhotoUrl;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCountForMe;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DmConversation({
    required this.id,
    required this.participantIds,
    required this.otherUserName,
    required this.otherUserPhotoUrl,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.unreadCountForMe,
    required this.createdAt,
    this.updatedAt,
  });

  /// [myUid] is used to parse the `unreadCount_{uid}` field and to derive
  /// the other participant's denormalized display fields.
  factory DmConversation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('DmConversation ${doc.id} has no data');

    final ids = List<String>.from(data['participantIds'] as List? ?? const []);
    final otherId = ids.firstWhere((id) => id != myUid, orElse: () => '');

    return DmConversation(
      id: doc.id,
      participantIds: ids,
      otherUserName: data['userName_$otherId'] as String? ?? '',
      otherUserPhotoUrl: data['userPhotoUrl_$otherId'] as String? ?? '',
      lastMessageText: data['lastMessageText'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      unreadCountForMe: (data['unreadCount_$myUid'] as int?) ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Serialises the structural fields. Unread counter fields and denormalized
  /// user fields are written separately by chat_service — do not include them here.
  Map<String, dynamic> toFirestore() {
    return {
      'participantIds': participantIds,
      'lastMessageText': lastMessageText,
      'lastMessageAt':
          lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'lastMessageSenderId': lastMessageSenderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  DmConversation copyWith({
    List<String>? participantIds,
    String? otherUserName,
    String? otherUserPhotoUrl,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    int? unreadCountForMe,
    DateTime? updatedAt,
  }) {
    return DmConversation(
      id: id,
      participantIds: participantIds ?? this.participantIds,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserPhotoUrl: otherUserPhotoUrl ?? this.otherUserPhotoUrl,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCountForMe: unreadCountForMe ?? this.unreadCountForMe,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}