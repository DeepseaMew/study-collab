import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/chat_message.dart';
import '../models/dm_conversation.dart';
import '../models/group_chat_meta.dart';

/// Chat service covering both DM and session group chat.
///
/// Firestore paths:
///   DM conversation:   chats/{dmId}                        (ADR 0012)
///   DM messages:       chats/{dmId}/messages/{autoId}
///   Group meta:        sessions/{sessionId}/groupChat/meta  (ADR 0013)
///   Group messages:    sessions/{sessionId}/messages/{autoId}
///
/// DM unread counters are flat fields `unreadCount_{uid}` on the chats doc.
/// Group unread counters are a map `unreadCounts: {uid: int}` updated via
/// dot-notation field paths (ADR 0014).
///
/// Friendship is enforced in both the service layer (ADR 0015) and Firestore
/// rules (ADR 0016). The 2-get-call cost per DM message send is accepted
/// (ADR 0016 / human lead decision).
///
/// NOTE: sendSessionMessage fetches the session's member list internally.
/// ADR 0017 proposes passing memberIds from the caller to avoid this read,
/// but the finalised interface does not include that parameter. Flagged as
/// deviation from ADR 0017 for the code-reviewer.
class ChatService {
  final FirebaseFirestore _firestore;

  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── DM helpers ──────────────────────────────────────────────────────────────

  /// Returns the deterministic DM conversation doc ID for two users.
  /// Consistent across all callers: sorted UIDs joined by '_'.
  String dmId(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Extracts the other participant UID from a DM conversation ID.
  /// Safe because Firebase Auth UIDs are alphanumeric (no underscores).
  String _otherParticipant(String conversationId, String myUid) {
    final sep = conversationId.indexOf('_');
    final uid1 = conversationId.substring(0, sep);
    final uid2 = conversationId.substring(sep + 1);
    return uid1 == myUid ? uid2 : uid1;
  }

  // ── Friendship guard ────────────────────────────────────────────────────────

  /// Throws [DataException] if [currentUid] and [otherUid] are not friends.
  Future<void> _assertFriends(String currentUid, String otherUid) async {
    final snap = await _firestore
        .collection(FirestoreCollections.friends)
        .doc(currentUid)
        .collection('userFriends')
        .doc(otherUid)
        .get();
    if (!snap.exists) {
      throw const DataException(
          'You must be friends to message this user');
    }
  }

  // ── DM: reads ───────────────────────────────────────────────────────────────

  /// Ensures a DM conversation doc exists and returns the conversation ID.
  ///
  /// Idempotent (`set` with merge: true). Throws [DataException] if the two
  /// users are not currently friends (ADR 0015).
  ///
  /// The `lastMessageAt` field is initialised to server timestamp on creation
  /// so the conversation appears in [watchMyConversations] results immediately.
  Future<String> getOrCreateDm({
    required String currentUserId,
    required String otherUserId,
  }) async {
    await _assertFriends(currentUserId, otherUserId);
    final id = dmId(currentUserId, otherUserId);
    final ref = _firestore.collection(FirestoreCollections.chats).doc(id);
    try {
      await ref.set(
        {
          'participantIds': ([currentUserId, otherUserId]..sort()),
          'lastMessageText': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageSenderId': null,
          'unreadCount_$currentUserId': 0,
          'unreadCount_$otherUserId': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return id;
    } catch (e) {
      throw DataException('Failed to open DM: $e');
    }
  }

  /// Watch the list of DM conversations for [uid], ordered by lastMessageAt DESC.
  ///
  /// Required composite index on `chats`:
  ///   participantIds (array-contains), lastMessageAt DESC
  Stream<List<DmConversation>> watchMyConversations(String uid) {
    return _firestore
        .collection(FirestoreCollections.chats)
        .where('participantIds', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DmConversation.fromFirestore(d, uid))
            .toList());
  }

  /// Watch messages in a DM conversation, ordered by sentAt ASC.
  Stream<List<ChatMessage>> watchDmMessages(String conversationId) {
    return _firestore
        .collection(FirestoreCollections.chats)
        .doc(conversationId)
        .collection(FirestoreCollections.messages)
        .orderBy('sentAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  // ── DM: writes ──────────────────────────────────────────────────────────────

  /// Send a text message in a DM.
  ///
  /// Atomic batch:
  ///   1. Add message doc.
  ///   2. Update conversation doc: lastMessage preview, lastMessageAt,
  ///      increment recipient's unread counter.
  ///
  /// Friendship is re-checked on every send (ADR 0015 — guard runs on every
  /// message, not only at conversation creation).
  Future<void> sendDmMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String text,
  }) async {
    final recipientId = _otherParticipant(conversationId, senderId);
    await _assertFriends(senderId, recipientId);

    final convRef =
        _firestore.collection(FirestoreCollections.chats).doc(conversationId);
    final msgRef =
        convRef.collection(FirestoreCollections.messages).doc();

    final preview =
        text.length > 100 ? '${text.substring(0, 100)}…' : text;

    try {
      final batch = _firestore.batch();
      batch.set(msgRef, {
        'senderId': senderId,
        'senderName': senderName,
        'senderPhotoUrl': senderPhotoUrl,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
      batch.update(convRef, {
        'lastMessageText': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'unreadCount_$recipientId': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to send message: $e');
    }
  }

  /// Reset [userId]'s unread count on a DM conversation to 0.
  /// Called when the user opens the conversation screen (fire-and-forget).
  Future<void> markDmRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.chats)
          .doc(conversationId)
          .update({'unreadCount_$userId': 0});
    } catch (e) {
      throw DataException('Failed to mark DM read: $e');
    }
  }

  // ── Group chat: reads ────────────────────────────────────────────────────────

  /// Watch messages in a session group chat, ordered by sentAt ASC.
  Stream<List<ChatMessage>> watchSessionMessages(String sessionId) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.messages)
        .orderBy('sentAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  /// Watch the group chat metadata doc (last message preview and unread count
  /// for [currentUserId]) for a session.
  Stream<GroupChatMeta?> watchGroupChatMeta({
    required String sessionId,
    required String currentUserId,
  }) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.groupChat)
        .doc('meta')
        .snapshots()
        .map((doc) => doc.exists
            ? GroupChatMeta.fromFirestore(doc, sessionId, currentUserId)
            : null);
  }

  // ── Group chat: writes ───────────────────────────────────────────────────────

  /// Send a text message in a session group chat.
  ///
  /// Fetches the session's confirmed member list to build the per-member
  /// unread counter increment map (all members except sender).
  ///
  /// Atomic batch:
  ///   1. Add message doc.
  ///   2. Update groupChat/meta: lastMessage preview, lastMessageAt,
  ///      increment each non-sender member's counter via dot-notation
  ///      (one Firestore write regardless of group size — ADR 0014).
  Future<void> sendSessionMessage({
    required String sessionId,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String text,
  }) async {
    final membersSnap = await _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.members)
        .get();

    final memberIds = membersSnap.docs.map((d) => d.id).toList();

    final metaRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.groupChat)
        .doc('meta');

    final msgRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.messages)
        .doc();

    final preview =
        text.length > 100 ? '${text.substring(0, 100)}…' : text;

    // Each dot-notation key increments one member's counter independently.
    final unreadIncrements = <String, dynamic>{};
    for (final uid in memberIds) {
      if (uid != senderId) {
        unreadIncrements['unreadCounts.$uid'] = FieldValue.increment(1);
      }
    }

    try {
      final batch = _firestore.batch();
      batch.set(msgRef, {
        'senderId': senderId,
        'senderName': senderName,
        'senderPhotoUrl': senderPhotoUrl,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
      batch.update(metaRef, {
        'lastMessageText': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
        'updatedAt': FieldValue.serverTimestamp(),
        ...unreadIncrements,
      });
      await batch.commit();
    } catch (e) {
      throw DataException('Failed to send group message: $e');
    }
  }

  /// Reset [userId]'s unread count in a session group chat to 0.
  /// Called when the user opens the chat screen (fire-and-forget).
  Future<void> markSessionChatRead({
    required String sessionId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.groupChat)
          .doc('meta')
          .update({'unreadCounts.$userId': 0});
    } catch (e) {
      throw DataException('Failed to mark group chat read: $e');
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());
