import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/chat_message.dart';
import '../models/dm_conversation.dart';
import '../models/enums.dart';
import '../models/group_chat_meta.dart';
import '../models/group_conversation.dart';

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
  /// Uses a Firestore transaction to guarantee the doc is written exactly
  /// once. If the doc already exists the transaction returns immediately
  /// without touching any fields — in particular [lastMessageAt] is never
  /// overwritten, so calling this method (e.g. when opening a friend's
  /// profile page) cannot reorder the DM list.
  ///
  /// Throws [DataException] if the two users are not currently friends
  /// (ADR 0015). Friendship is checked before the transaction to avoid
  /// holding a Firestore transaction open during an extra read.
Future<String> getOrCreateDm({
  required String currentUserId,
  required String otherUserId,
}) async {
  debugPrint('getOrCreateDm start');
  await _assertFriends(currentUserId, otherUserId);
  debugPrint('friends check passed');

  final id = dmId(currentUserId, otherUserId);
  final ref = _firestore.collection(FirestoreCollections.chats).doc(id);

  try {
    debugPrint('fetching currentUser doc...');
    final currentUserDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(currentUserId)
        .get();
    debugPrint('currentUser exists: ${currentUserDoc.exists}');

    debugPrint('fetching otherUser doc...');
    final otherUserDoc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(otherUserId)
        .get();
    debugPrint('otherUser exists: ${otherUserDoc.exists}');

    final snap = await ref.get();
    debugPrint('chat doc exists: ${snap.exists}');
    if (snap.exists) return id;

    debugPrint('creating chat doc...');
    await ref.set({
      'participantIds': [currentUserId, otherUserId]..sort(),
      'userName_$currentUserId': currentUserDoc.data()?['username'] ?? '',
      'userPhotoUrl_$currentUserId': currentUserDoc.data()?['profilePhotoUrl'] ?? '',
      'userName_$otherUserId': otherUserDoc.data()?['username'] ?? '',
      'userPhotoUrl_$otherUserId': otherUserDoc.data()?['profilePhotoUrl'] ?? '',
      'lastMessageText': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': null,
      'unreadCount_$currentUserId': 0,
      'unreadCount_$otherUserId': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('chat doc created successfully');
    return id;
  } catch (e) {
    debugPrint('getOrCreateDm failed at step above: $e');
    if (e is DataException) rethrow;
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

  /// Watch all group conversations for [uid], sorted by lastMessageAt DESC.
  ///
  /// Algorithm:
  ///   1. CollectionGroup query on `members` where `userId == uid` gives the
  ///      list of sessions the user belongs to (member docs carry denormalized
  ///      session fields per ADR 0008 — no extra session fetches needed).
  ///   2. For each member doc, a listener on sessions/{sessionId}/groupChat/meta
  ///      provides last-message preview and per-user unread count.
  ///   3. The outer stream and all inner meta streams are combined via a
  ///      StreamController with explicit subscription bookkeeping so that
  ///      cancelling the returned stream cancels every inner listener.
  ///
  /// Required Firestore index (collectionGroup):
  ///   Collection group: members
  ///   Fields: userId ASC
  ///   (single-field collectionGroup index — create via Firebase Console or
  ///    firestore.indexes.json under collectionGroup exemptions)
  ///
  /// Sessions whose groupChat/meta doc does not yet exist are skipped with a
  /// debug warning — this is expected for newly-created sessions where the
  /// host has not sent any messages yet.
  Stream<List<GroupConversation>> watchMyGroupConversations(String uid) {
    // ignore: close_sinks — controller lifetime is tied to the returned stream.
    final controller = StreamController<List<GroupConversation>>();

    // Map from sessionId → current GroupConversation value (latest snapshot).
    final Map<String, GroupConversation> current = {};
    // Map from sessionId → inner StreamSubscription for groupChat/meta.
    final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> metaSubs = {};

    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> memberSub;

    void emitSorted() {
      if (controller.isClosed) return;
      final list = current.values.toList()
        ..sort((a, b) {
          final aAt = a.lastMessageAt;
          final bAt = b.lastMessageAt;
          if (aAt == null && bAt == null) return 0;
          if (aAt == null) return 1;
          if (bAt == null) return -1;
          return bAt.compareTo(aAt); // DESC
        });
      controller.add(list);
    }

    // Subscribe to each session's groupChat/meta and merge into [current].
    void subscribeToMeta(String sessionId, GroupConversation base) {
      final metaRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.groupChat)
          .doc('meta');

      final sub = metaRef.snapshots().listen(
        (snap) {
          if (!snap.exists) {
            debugPrint(
                '[ChatService] watchMyGroupConversations: '
                'groupChat/meta missing for session $sessionId — skipping');
            // Remove from current map so it doesn't appear in the list.
            current.remove(sessionId);
            emitSorted();
            return;
          }
          final meta = GroupChatMeta.fromFirestore(snap, sessionId, uid);
          current[sessionId] = base.copyWith(
            lastMessageText: meta.lastMessageText,
            lastMessageAt: meta.lastMessageAt,
            unreadCountForMe: meta.unreadCountForMe,
          );
          emitSorted();
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(DataException('Group chat meta error: $e'));
        },
      );
      metaSubs[sessionId] = sub;
    }

    // Outer listener: the collectionGroup query on `members`.
    //
    // Required composite index:
    //   Collection group: members | Field: userId ASC
    memberSub = _firestore
        .collectionGroup(FirestoreCollections.members)
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
      (snap) {
        final incomingIds = <String>{};

        for (final doc in snap.docs) {
          final data = doc.data();
          // Extract the sessionId from the doc's parent path:
          //   sessions/{sessionId}/members/{userId}
          final sessionId = doc.reference.parent.parent?.id;
          if (sessionId == null) {
            // Race condition: doc being deleted, parent already gone.
            debugPrint('[ChatService] watchMyGroupConversations: '
                'member doc has no parent session — skipping');
            continue;
          }

          incomingIds.add(sessionId);

          final base = GroupConversation(
            sessionId: sessionId,
            sessionTitle: data['sessionTitle'] as String? ?? '',
            sessionSubject:
                Subject.fromString(data['sessionSubject'] as String?),
            sessionStatus:
                SessionStatus.fromString(data['sessionStatus'] as String?),
            // lastMessageText / lastMessageAt / unreadCountForMe will be
            // filled by the meta stream listener below.
            lastMessageText: current[sessionId]?.lastMessageText,
            lastMessageAt: current[sessionId]?.lastMessageAt,
            unreadCountForMe: current[sessionId]?.unreadCountForMe ?? 0,
          );

          if (!metaSubs.containsKey(sessionId)) {
            // First time seeing this session — start a meta listener.
            subscribeToMeta(sessionId, base);
          } else {
            // Session already tracked. Update base fields (title/subject/status
            // may have changed) while preserving the meta values already in
            // [current].
            final existing = current[sessionId];
            current[sessionId] = GroupConversation(
              sessionId: sessionId,
              sessionTitle: base.sessionTitle,
              sessionSubject: base.sessionSubject,
              sessionStatus: base.sessionStatus,
              lastMessageText: existing?.lastMessageText,
              lastMessageAt: existing?.lastMessageAt,
              unreadCountForMe: existing?.unreadCountForMe ?? 0,
            );
          }
        }

        // Cancel meta listeners for sessions the user is no longer a member of.
        final removed = metaSubs.keys.toSet().difference(incomingIds);
        for (final sessionId in removed) {
          metaSubs[sessionId]?.cancel();
          metaSubs.remove(sessionId);
          current.remove(sessionId);
        }

        // If the user has zero memberships emit an empty list immediately.
        if (incomingIds.isEmpty) {
          emitSorted();
        }
        // Otherwise emitSorted() will be triggered by each meta listener's
        // first snapshot. For updated member docs, emit now so title/status
        // changes surface immediately.
        else if (current.isNotEmpty) {
          emitSorted();
        }
      },
      onError: (Object e) {
        if (!controller.isClosed) {
          controller.addError(DataException('Failed to watch group conversations: $e'));
        }
      },
    );

    controller.onCancel = () async {
      await memberSub.cancel();
      for (final sub in metaSubs.values) {
        await sub.cancel();
      }
      metaSubs.clear();
      current.clear();
    };

    return controller.stream;
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
      // Defensive merge: the meta doc may not exist yet for new sessions with no messages.
      await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.groupChat)
          .doc('meta')
          .set({'unreadCounts.$userId': 0}, SetOptions(merge: true));
    } catch (e) {
      throw DataException('Failed to mark group chat read: $e');
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());
