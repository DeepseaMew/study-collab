import 'package:cloud_firestore/cloud_firestore.dart';

/// A single chat message in either a DM or a session group chat.
///
/// DM path:    chats/{dmId}/messages/{autoId}
/// Group path: sessions/{sessionId}/messages/{autoId}
///
/// Schema per ADR 0012 / 0013, extended with denormalised sender fields
/// so message rows can render without a user doc lookup.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.text,
    required this.sentAt,
  });

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('ChatMessage ${doc.id} has no data');
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'text': text,
      'sentAt': Timestamp.fromDate(sentAt),
    };
  }

  ChatMessage copyWith({
    String? senderName,
    String? senderPhotoUrl,
    String? text,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      text: text ?? this.text,
      sentAt: sentAt,
    );
  }
}
