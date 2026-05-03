import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  file,
  system;

  static MessageType fromString(String? value) {
    return MessageType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => MessageType.text,
    );
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final MessageType type;
  final String text;
  final String? attachmentUrl;
  final String? attachmentName;
  final int? attachmentSizeBytes;
  final String? attachmentMimeType;
  final DateTime sentAt;
  final List<String> readBy;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    this.type = MessageType.text,
    this.text = '',
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentSizeBytes,
    this.attachmentMimeType,
    required this.sentAt,
    this.readBy = const [],
  });

  bool get isText   => type == MessageType.text;
  bool get isFile   => type == MessageType.file;
  bool get isSystem => type == MessageType.system;
  bool get hasAttachment => attachmentUrl != null;
  bool isReadBy(String userId)  => readBy.contains(userId);
  bool isSentBy(String userId)  => senderId == userId;

  String get displayAttachmentSize {
    final size = attachmentSizeBytes;
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  factory Message.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String chatId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('Message document ${doc.id} has no data');
    return Message(
      id: doc.id,
      chatId: chatId,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      type: MessageType.fromString(data['type'] as String?),
      text: data['text'] as String? ?? '',
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentName: data['attachmentName'] as String?,
      attachmentSizeBytes: data['attachmentSizeBytes'] as int?,
      attachmentMimeType: data['attachmentMimeType'] as String?,
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readBy: List<String>.from(data['readBy'] as List? ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'type': type.name,
      'text': text,
      'attachmentUrl': attachmentUrl,
      'attachmentName': attachmentName,
      'attachmentSizeBytes': attachmentSizeBytes,
      'attachmentMimeType': attachmentMimeType,
      'sentAt': Timestamp.fromDate(sentAt),
      'readBy': readBy,
    };
  }

  Message copyWith({List<String>? readBy}) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      type: type,
      text: text,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
      attachmentSizeBytes: attachmentSizeBytes,
      attachmentMimeType: attachmentMimeType,
      sentAt: sentAt,
      readBy: readBy ?? this.readBy,
    );
  }
}