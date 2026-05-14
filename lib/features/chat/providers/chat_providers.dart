import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_providers.dart';
import '../../../models/chat_message.dart';
import '../../../models/dm_conversation.dart';
import '../../../models/group_chat_meta.dart';
import '../../../models/group_conversation.dart';
import '../../../services/chat_service.dart';

// ── DM: current user's conversation list ──────────────────────────────────────

/// DM conversation list for the signed-in user, ordered by lastMessageAt DESC.
///
/// Depends on [authStateProvider] to obtain the current uid. Returns an empty
/// list while the auth state is loading or when no user is signed in.
final userDmConversationsProvider = StreamProvider<List<DmConversation>>((ref) {
  final authAsync = ref.watch(authStateProvider);
  return authAsync.when(
    data: (user) {
      if (user == null) return Stream.value(const []);
      return ref.watch(chatServiceProvider).watchMyConversations(user.id);
    },
    loading: () => Stream.value(const []),
    error: (e, _) => Stream.value(const []),
  );
});

/// Look up a single DmConversation by its doc id.
///
/// Derived from [userDmConversationsProvider] — no extra Firestore read.
/// Returns null if the conversation is not found in the current list.
final dmConversationByIdProvider = Provider.family<DmConversation?, String>((
  ref,
  conversationId,
) {
  return ref
      .watch(userDmConversationsProvider)
      .maybeWhen(
        data: (list) {
          try {
            return list.firstWhere((c) => c.id == conversationId);
          } catch (_) {
            return null;
          }
        },
        orElse: () => null,
      );
});

// ── DM: legacy family kept for callers that supply an explicit uid ─────────────

/// DM conversation list for an explicit [userId].
/// Prefer [userDmConversationsProvider] in screens — use this family only when
/// a non-current-user uid is required (e.g. admin views).
final dmConversationsProvider =
    StreamProvider.family<List<DmConversation>, String>(
      (ref, userId) =>
          ref.watch(chatServiceProvider).watchMyConversations(userId),
    );

// ── DM: message stream ────────────────────────────────────────────────────────

/// Message stream for a specific DM conversation, ordered by sentAt ASC.
final dmMessagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, conversationId) =>
      ref.watch(chatServiceProvider).watchDmMessages(conversationId),
);

// ── Group chat: conversation list ─────────────────────────────────────────────

/// Group conversation list for a given [uid], ordered by lastMessageAt DESC.
///
/// Use [userGroupConversationsProvider] in screens where the current user's
/// conversations are needed — this family is the underlying implementation.
final groupConversationsProvider =
    StreamProvider.family<List<GroupConversation>, String>(
      (ref, uid) =>
          ref.watch(chatServiceProvider).watchMyGroupConversations(uid),
    );

/// Group conversation list for the signed-in user, ordered by lastMessageAt
/// DESC. Returns an empty list while auth is loading or user is signed out.
final userGroupConversationsProvider = StreamProvider<List<GroupConversation>>((
  ref,
) {
  final authAsync = ref.watch(authStateProvider);
  return authAsync.when(
    data: (user) {
      if (user == null) return Stream.value(const []);
      return ref.watch(chatServiceProvider).watchMyGroupConversations(user.id);
    },
    loading: () => Stream.value(const []),
    error: (e, _) => Stream.value(const []),
  );
});

// ── Group chat: message stream ────────────────────────────────────────────────

/// Message stream for a session's group chat, ordered by sentAt ASC.
final sessionMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>(
      (ref, sessionId) =>
          ref.watch(chatServiceProvider).watchSessionMessages(sessionId),
    );

// ── Group chat: metadata ──────────────────────────────────────────────────────

/// Group chat metadata (last message preview + unread count) for a session.
///
/// Family param is a record: (sessionId, currentUserId).
final groupChatMetaProvider =
    StreamProvider.family<GroupChatMeta?, (String, String)>((ref, args) {
      final (sessionId, userId) = args;
      return ref
          .watch(chatServiceProvider)
          .watchGroupChatMeta(sessionId: sessionId, currentUserId: userId);
    });

// ── Unread totals (derived) ───────────────────────────────────────────────────

/// Total unread DM count across all of the current user's conversations.
/// Returns 0 while loading or on error.
final unreadDmTotalProvider = Provider<int>((ref) {
  return ref
      .watch(userDmConversationsProvider)
      .maybeWhen(
        data: (list) => list.fold<int>(0, (sum, c) => sum + c.unreadCountForMe),
        orElse: () => 0,
      );
});

/// Total unread group chat count across all of the current user's group
/// conversations. Returns 0 while loading or on error.
final unreadGroupTotalProvider = Provider<int>((ref) {
  return ref
      .watch(userGroupConversationsProvider)
      .maybeWhen(
        data: (list) => list.fold<int>(0, (sum, c) => sum + c.unreadCountForMe),
        orElse: () => 0,
      );
});
