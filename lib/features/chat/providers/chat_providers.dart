import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_message.dart';
import '../../../models/dm_conversation.dart';
import '../../../models/group_chat_meta.dart';
import '../../../services/chat_service.dart';

/// DM conversation list for the current user, ordered by lastMessageAt DESC.
final dmConversationsProvider =
    StreamProvider.family<List<DmConversation>, String>(
  (ref, userId) =>
      ref.watch(chatServiceProvider).watchMyConversations(userId),
);

/// Message stream for a specific DM conversation, ordered by sentAt ASC.
final dmMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>(
  (ref, conversationId) =>
      ref.watch(chatServiceProvider).watchDmMessages(conversationId),
);

/// Message stream for a session's group chat, ordered by sentAt ASC.
final sessionMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>(
  (ref, sessionId) =>
      ref.watch(chatServiceProvider).watchSessionMessages(sessionId),
);

/// Group chat metadata (last message preview + unread count) for a session.
/// Family param is a record: (sessionId, currentUserId).
final groupChatMetaProvider =
    StreamProvider.family<GroupChatMeta?, (String, String)>(
  (ref, args) {
    final (sessionId, userId) = args;
    return ref.watch(chatServiceProvider).watchGroupChatMeta(
          sessionId: sessionId,
          currentUserId: userId,
        );
  },
);
