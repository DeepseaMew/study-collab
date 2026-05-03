import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/message.dart';

/// Handles: DMs, group chats, sending messages
class ChatService {
  // ignore: unused_field
  final FirebaseFirestore _firestore;

  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;


  Stream<List<Chat>> watchMyChats(String userId) {
    throw UnimplementedError();
  }


  Stream<List<Message>> watchMessages(String chatId) {
    throw UnimplementedError();
  }


  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    String? senderPhotoUrl,
  }) {
    throw UnimplementedError();
  }


  Future<Chat> getOrCreateDirectChat({
    required String myUserId,
    required String myUsername,
    required String otherUserId,
    required String otherUsername,
    String? myPhotoUrl,
    String? otherPhotoUrl,
  }) {
    throw UnimplementedError();
  }


  Future<void> markAsRead({
    required String chatId,
    required String userId,
  }) {
    throw UnimplementedError();
  }
}

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});