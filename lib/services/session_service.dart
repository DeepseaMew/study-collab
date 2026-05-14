import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/app_notification.dart';
import '../models/enums.dart';
import '../models/participant.dart';
import '../models/session.dart';

/// Session service.
///
/// Firestore paths:
///   sessions/{sessionId}
///   sessions/{sessionId}/members/{userId}  ← member doc, doc ID = userId
///   users/{userId}                          ← sessionsCount incremented here
///   users/{userId}/notifications/{autoId}   ← cancel / postpone alerts
///
/// Denormalized fields on member docs (card-render cache — ADR 0008):
///   sessionTitle, sessionStartTime, sessionEndTime,
///   sessionStatus, sessionSubject, hostId
/// These are updated atomically when the host calls editSession / cancelSession
/// / postponeSession.
///
/// TODO: When a host updates their username or profilePhotoUrl (user_service),
/// fan-out to all session docs where hostId == userId to update hostName and
/// hostPhotoUrl. This is NOT done here; it belongs in user_service.dart once
/// the profile-edit flow is built out.
class SessionService {
  final FirebaseFirestore _firestore;

  SessionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Password helpers ────────────────────────────────────────────────────────

  /// Hash [plainText] with a random 16-byte salt using SHA-256.
  ///
  /// Returns `"<sha256hex>:<base64salt>"`.
  /// NEVER log plainText.
  String _hashPassword(String plainText) {
    final rng = Random.secure();
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final passwordBytes = utf8.encode(plainText);
    final combined = Uint8List(saltBytes.length + passwordBytes.length)
      ..setRange(0, saltBytes.length, saltBytes)
      ..setRange(saltBytes.length, saltBytes.length + passwordBytes.length,
          passwordBytes);
    final digest = sha256.convert(combined);
    final saltBase64 = base64.encode(saltBytes);
    return '${digest.toString()}:$saltBase64';
  }

  // ── Batch chunking ──────────────────────────────────────────────────────────

  /// Commits [ops] in batches of [chunkSize] (default 450, safely under the
  /// Firestore 500-op limit).
  Future<void> _commitInChunks(
    List<void Function(WriteBatch)> ops, {
    int chunkSize = 450,
  }) async {
    if (ops.isEmpty) return;
    for (int i = 0; i < ops.length; i += chunkSize) {
      final batch = _firestore.batch();
      final end = (i + chunkSize).clamp(0, ops.length);
      for (final op in ops.sublist(i, end)) {
        op(batch);
      }
      try {
        await batch.commit();
      } catch (e) {
        // Each chunk is committed independently — a failure here means ops
        // in subsequent chunks were NOT applied. Full transactional consistency
        // across chunks would require a Cloud Function (out of scope, ADR 0008).
        debugPrint('[session_service] batch chunk ${i ~/ chunkSize} failed: $e');
        rethrow;
      }
    }
  }

  // ── Reads ───────────────────────────────────────────────────────────────────

  /// Watch a single session in real time.
  Stream<Session?> watchSession(String sessionId) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return Session.fromFirestore(doc);
    });
  }

  /// Watch all public upcoming sessions ordered by start time ASC.
  ///
  /// Required composite index on `sessions`:
  ///   visibility ASC, status ASC, startTime ASC
  /// (already documented in docs/firestore-indexes.md)
  Stream<List<Session>> watchPublicSessions() {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .where('visibility', isEqualTo: SessionVisibility.public.name)
        .where('status', isEqualTo: SessionStatus.upcoming.name)
        .orderBy('startTime')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Session.fromFirestore(d)).toList());
  }

  /// Watch all sessions hosted by [userId] ordered by start time DESC.
  ///
  /// Required composite index on `sessions`:
  ///   hostId ASC, startTime DESC
  Stream<List<Session>> watchHostedSessions(String userId) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .where('hostId', isEqualTo: userId)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Session.fromFirestore(d)).toList());
  }

  /// Watch public sessions hosted by [userId] ordered by start time DESC.
  /// Used for other-user profile views (hides private sessions).
  ///
  /// Required composite index on `sessions`:
  ///   hostId ASC, visibility ASC, startTime DESC
  Stream<List<Session>> watchHostedPublicSessions(String userId) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .where('hostId', isEqualTo: userId)
        .where('visibility', isEqualTo: SessionVisibility.public.name)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Session.fromFirestore(d)).toList());
  }

  /// Watch public upcoming sessions filtered by [subject], ordered by start time ASC.
  ///
  /// Required composite index on `sessions`:
  ///   visibility ASC, status ASC, subject ASC, startTime ASC
  Stream<List<Session>> browseBySubject(Subject subject) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .where('visibility', isEqualTo: SessionVisibility.public.name)
        .where('status', isEqualTo: SessionStatus.upcoming.name)
        .where('subject', isEqualTo: subject.name)
        .orderBy('startTime')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Session.fromFirestore(d)).toList());
  }

  /// One-shot fetch of a session by ID. Returns null if not found.
  Future<Session?> getSession(String sessionId) async {
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .get();
      if (!doc.exists) return null;
      return Session.fromFirestore(doc);
    } catch (e) {
      throw DataException('Failed to fetch session: $e');
    }
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  /// Create a new session.
  ///
  /// - If [session].visibility is private, [plainTextPassword] is required
  ///   and will be hashed before storage. Never stored in plain text.
  /// - Atomically:
  ///     1. Sets the session doc (participantCount = 1).
  ///     2. Sets the host member doc with all card-render fields.
  ///     3. Increments users/{hostId}.sessionsCount.
  ///
  /// Returns the new sessionId.
  Future<String> createSession({
    required Session session,
    String? plainTextPassword,
  }) async {
    if (session.visibility == SessionVisibility.private &&
        (plainTextPassword == null || plainTextPassword.isEmpty)) {
      throw const DataException(
          'A password is required for private sessions');
    }

    String? passwordHash;
    if (session.visibility == SessionVisibility.private &&
        plainTextPassword != null &&
        plainTextPassword.isNotEmpty) {
      passwordHash = _hashPassword(plainTextPassword);
    }

    final sessionRef =
        _firestore.collection(FirestoreCollections.sessions).doc();

    final now = FieldValue.serverTimestamp();

    final sessionData = {
      'title': session.title,
      'subject': session.subject.name,
      'description': session.description,
      'visibility': session.visibility.name,
      'hostId': session.hostId,
      'hostName': session.hostName,
      'hostPhotoUrl': session.hostPhotoUrl,
      'startTime': Timestamp.fromDate(session.startTime),
      'endTime': Timestamp.fromDate(session.endTime),
      'location': session.location,
      'capacity': session.capacity,
      'participantCount': FieldValue.increment(1),
      'status': SessionStatus.upcoming.name,
      'reviewsEnabled': session.reviewsEnabled,
      'createdAt': now,
      'updatedAt': now,
      'passwordHash': ?passwordHash,
      'studentYear': ?session.studentYear,
      if (session.academicLevel != null)
        'academicLevel': session.academicLevel!.name,
      'hashtags': session.hashtags,
    };

    final hostMemberRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionRef.id)
        .collection(FirestoreCollections.members)
        .doc(session.hostId);

    final hostMemberData = {
      'userId': session.hostId,
      'username': session.hostName,
      'profilePhotoUrl': session.hostPhotoUrl,
      'role': ParticipantRole.host.name,
      'joinedAt': now,
      'attended': false,
      'sessionTitle': session.title,
      'sessionStartTime': Timestamp.fromDate(session.startTime),
      'sessionEndTime': Timestamp.fromDate(session.endTime),
      'sessionStatus': SessionStatus.upcoming.name,
      'sessionSubject': session.subject.name,
      'hostId': session.hostId,
    };

    final userRef = _firestore
        .collection(FirestoreCollections.users)
        .doc(session.hostId);

    // GroupChat metadata singleton — created atomically with the session doc
    // so the doc always exists before the first member opens chat (ADR 0013).
    final groupChatMetaRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionRef.id)
        .collection(FirestoreCollections.groupChat)
        .doc('meta');

    try {
      final batch = _firestore.batch();
      batch.set(sessionRef, sessionData);
      batch.set(hostMemberRef, hostMemberData);
      batch.update(userRef, {'sessionsCount': FieldValue.increment(1)});
      batch.set(groupChatMetaRef, {
        'lastMessageText': '',
        'lastMessageAt': now,
        'lastMessageSenderId': null,
        'unreadCounts': <String, int>{},
        'createdAt': now,
        'updatedAt': now,
      });
      await batch.commit();
      return sessionRef.id;
    } catch (e) {
      throw DataException('Failed to create session: $e');
    }
  }

  /// Edit session fields.
  ///
  /// [updates] is a map of Firestore field names to new values (caller-supplied).
  /// Always sets `updatedAt = serverTimestamp()`.
  ///
  /// [updatedCardFields] is the subset of card-render field names that changed.
  /// If non-null and non-empty, fans out those changes to all member docs in a
  /// batched write.
  ///
  /// Card-render field name mapping:
  ///   'title'     → 'sessionTitle'   on member docs
  ///   'startTime' → 'sessionStartTime'
  ///   'endTime'   → 'sessionEndTime'
  ///   'status'    → 'sessionStatus'
  ///   'subject'   → 'sessionSubject'
  Future<void> editSession({
    required String sessionId,
    required String callerUid,
    required Map<String, dynamic> updates,
    List<String>? updatedCardFields,
  }) async {
    // Defense-in-depth on top of Firestore rules.
    final snap = await _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .get();
    if (!snap.exists) throw const DataException('Session not found');
    if ((snap.data()!['hostId'] as String?) != callerUid) {
      throw const DataException('Only the host can edit this session');
    }

    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId);

    final sessionUpdates = Map<String, dynamic>.from(updates)
      ..['updatedAt'] = FieldValue.serverTimestamp();

    try {
      if (updatedCardFields == null || updatedCardFields.isEmpty) {
        await sessionRef.update(sessionUpdates);
        return;
      }

      // Build member-doc fan-out payload from session-level field names.
      final memberUpdate = <String, dynamic>{};
      for (final field in updatedCardFields) {
        if (updates.containsKey(field)) {
          final memberField = _cardFieldName(field);
          if (memberField != null) memberUpdate[memberField] = updates[field];
        }
      }

      // Fetch all member doc refs for fan-out.
      final membersSnap = await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .get();

      final ops = <void Function(WriteBatch)>[];
      ops.add((b) => b.update(sessionRef, sessionUpdates));

      if (memberUpdate.isNotEmpty) {
        for (final memberDoc in membersSnap.docs) {
          final ref = memberDoc.reference;
          ops.add((b) => b.update(ref, memberUpdate));
        }
      }

      await _commitInChunks(ops);
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to edit session: $e');
    }
  }

  /// Cancel a session.
  ///
  /// Chunked batch (450 ops per batch) per ADR 0010:
  ///   1. Updates session doc: status = 'cancelled', updatedAt = now.
  ///   2. Updates all member docs: sessionStatus = 'cancelled'.
  ///   3. Deletes all pending JoinRequest docs.
  ///   4. Decrements sessionsCount on every NON-HOST member's user doc.
  ///   5. Writes AppNotification (sessionCancelled) to each non-host member.
  ///
  /// Host's sessionsCount is NOT decremented on cancel.
  Future<void> cancelSession({
    required String sessionId,
    required String hostId,
    required String hostName,
  }) async {
    try {
      final sessionRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId);

      final results = await Future.wait([
        sessionRef.get(),
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .get(),
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .get(),
      ]);

      final sessionSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (!sessionSnap.exists) throw const DataException('Session not found');
      final session = Session.fromFirestore(sessionSnap);
      final membersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final requestsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;

      final ops = <void Function(WriteBatch)>[];

      // 1. Update session doc.
      ops.add((b) => b.update(sessionRef, {
            'status': SessionStatus.cancelled.name,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

      // 2. Update all member docs + 4. decrement sessionsCount for non-hosts
      //    + 5. notification to non-hosts.
      for (final memberDoc in membersSnap.docs) {
        final memberId = memberDoc.id;
        final memberRef = memberDoc.reference;

        // Update sessionStatus on member doc.
        ops.add((b) => b.update(memberRef, {
              'sessionStatus': SessionStatus.cancelled.name,
            }));

        if (memberId != hostId) {
          // 4. Decrement sessionsCount.
          final userRef = _firestore
              .collection(FirestoreCollections.users)
              .doc(memberId);
          ops.add((b) =>
              b.update(userRef, {'sessionsCount': FieldValue.increment(-1)}));

          // 5. Notification.
          final notifRef = _firestore
              .collection(FirestoreCollections.users)
              .doc(memberId)
              .collection(FirestoreCollections.notifications)
              .doc();
          ops.add((b) => b.set(notifRef, {
                'type': NotificationType.sessionCancelled.name,
                'sessionId': sessionId,
                'sessionTitle': session.title,
                'fromUserId': hostId,
                'fromUsername': hostName,
                'fromUserPhotoUrl': null,
                'body': null,
                'chatId': null,
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              }));
        }
      }

      // 3. Delete all pending JoinRequest docs.
      for (final reqDoc in requestsSnap.docs) {
        final ref = reqDoc.reference;
        ops.add((b) => b.delete(ref));
      }

      await _commitInChunks(ops);
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to cancel session: $e');
    }
  }

  /// Postpone a session to new start/end times.
  ///
  /// Batch per ADR 0010:
  ///   1. Updates session doc: startTime, endTime, updatedAt.
  ///   2. Updates all member docs: sessionStartTime, sessionEndTime.
  ///   3. Leaves pending JoinRequest docs untouched.
  ///   4. Writes AppNotification (sessionPostponed) to each member (incl. host).
  Future<void> postponeSession({
    required String sessionId,
    required String hostId,
    required String hostName,
    required DateTime newStartTime,
    required DateTime newEndTime,
  }) async {
    try {
      final sessionRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId);

      final results = await Future.wait([
        sessionRef.get(),
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .get(),
      ]);

      final sessionSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (!sessionSnap.exists) throw const DataException('Session not found');
      final session = Session.fromFirestore(sessionSnap);
      final membersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

      final ops = <void Function(WriteBatch)>[];

      // 1. Update session doc.
      ops.add((b) => b.update(sessionRef, {
            'startTime': Timestamp.fromDate(newStartTime),
            'endTime': Timestamp.fromDate(newEndTime),
            'updatedAt': FieldValue.serverTimestamp(),
          }));

      // 2. Update member docs + 4. notification to all members.
      for (final memberDoc in membersSnap.docs) {
        final memberId = memberDoc.id;
        final memberRef = memberDoc.reference;

        ops.add((b) => b.update(memberRef, {
              'sessionStartTime': Timestamp.fromDate(newStartTime),
              'sessionEndTime': Timestamp.fromDate(newEndTime),
            }));

        final notifRef = _firestore
            .collection(FirestoreCollections.users)
            .doc(memberId)
            .collection(FirestoreCollections.notifications)
            .doc();
        ops.add((b) => b.set(notifRef, {
              'type': NotificationType.sessionPostponed.name,
              'sessionId': sessionId,
              'sessionTitle': session.title,
              'fromUserId': hostId,
              'fromUsername': hostName,
              'fromUserPhotoUrl': null,
              'body': newStartTime.toIso8601String(),
              'chatId': null,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            }));
      }

      await _commitInChunks(ops);
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to postpone session: $e');
    }
  }

  /// End a session immediately: sets status → completed and updates endTime to
  /// now, so the ratings system can accept ratings right away — contrast with
  /// cancelSession which sets status → cancelled and leaves endTime unchanged.
  ///
  /// Chunked batch (450 ops per batch) per ADR 0010:
  ///   1. Updates session doc: status = 'completed', endTime = now,
  ///      updatedAt = serverTimestamp().
  ///   2. Updates all member docs: sessionStatus = 'completed',
  ///      sessionEndTime = now.
  ///   3. Writes AppNotification (sessionEnded) to each member (incl. host).
  ///
  /// Requires [hostId] == session.hostId and session.status == 'ongoing'.
  /// Does NOT touch sessionsCount, joinRequests, members, group chat, or files.
  Future<void> endSession({
    required String sessionId,
    required String hostId,
    required String hostName,
  }) async {
    try {
      final sessionRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId);

      final results = await Future.wait([
        sessionRef.get(),
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .get(),
      ]);

      final sessionSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (!sessionSnap.exists) throw const DataException('Session not found');
      final session = Session.fromFirestore(sessionSnap);

      if (session.hostId != hostId) {
        throw const DataException('Only the host can end this session');
      }
      if (session.status != SessionStatus.ongoing) {
        throw const DataException('Only ongoing sessions can be ended');
      }

      final membersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

      // Shared timestamp so session doc and all member docs agree on endTime.
      final now = Timestamp.now();

      final ops = <void Function(WriteBatch)>[];

      // 1. Update session doc.
      ops.add((b) => b.update(sessionRef, {
            'status': SessionStatus.completed.name,
            'endTime': now,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

      // 2. Update each member doc + 3. notification to all members (incl. host).
      for (final memberDoc in membersSnap.docs) {
        final memberId = memberDoc.id;
        final memberRef = memberDoc.reference;

        // 2. Denormalize completed status and updated endTime onto member doc.
        ops.add((b) => b.update(memberRef, {
              'sessionStatus': SessionStatus.completed.name,
              'sessionEndTime': now,
            }));

        // 3. Notification.
        final notifRef = _firestore
            .collection(FirestoreCollections.users)
            .doc(memberId)
            .collection(FirestoreCollections.notifications)
            .doc();
        ops.add((b) => b.set(notifRef, {
              'type': NotificationType.sessionEnded.name,
              'sessionId': sessionId,
              'sessionTitle': session.title,
              'fromUserId': hostId,
              'fromUsername': hostName,
              'fromUserPhotoUrl': null,
              'body': null,
              'chatId': null,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            }));
      }

      await _commitInChunks(ops);
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to end session: $e');
    }
  }

  /// Delete a session and all its subcollection documents.
  ///
  /// Atomic across chunks (per _commitInChunks semantics):
  ///   - Deletes all member docs, all joinRequest docs.
  ///   - Decrements sessionsCount on every non-host member.
  ///   - Deletes the session doc last.
  ///
  /// Note: member docs are deleted (unlike cancelSession which keeps them as
  /// history). deleteSession is permanent — caller should confirm intent.
  Future<void> deleteSession({
    required String sessionId,
    required String hostId,
  }) async {
    try {
      final sessionRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId);

      final results = await Future.wait([
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .get(),
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .get(),
        // ADR 0013: delete group chat messages with the session.
        _firestore
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.messages)
            .get(),
      ]);

      final membersSnap = results[0];
      final requestsSnap = results[1];
      final messagesSnap = results[2];

      final ops = <void Function(WriteBatch)>[];

      for (final memberDoc in membersSnap.docs) {
        final memberId = memberDoc.id;
        ops.add((b) => b.delete(memberDoc.reference));
        if (memberId != hostId) {
          final userRef = _firestore
              .collection(FirestoreCollections.users)
              .doc(memberId);
          ops.add((b) =>
              b.update(userRef, {'sessionsCount': FieldValue.increment(-1)}));
        }
      }

      for (final reqDoc in requestsSnap.docs) {
        ops.add((b) => b.delete(reqDoc.reference));
      }

      // ADR 0013: delete all group chat messages.
      for (final msgDoc in messagesSnap.docs) {
        ops.add((b) => b.delete(msgDoc.reference));
      }

      // ADR 0013: delete the groupChat/meta singleton doc.
      final groupChatMetaRef = _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.groupChat)
          .doc('meta');
      ops.add((b) => b.delete(groupChatMetaRef));

      ops.add((b) => b.delete(sessionRef));

      await _commitInChunks(ops);
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to delete session: $e');
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Maps a session-level field name to its denormalized name on member docs.
  /// Returns null if the field has no member-doc counterpart.
  String? _cardFieldName(String sessionField) {
    const map = {
      'title': 'sessionTitle',
      'startTime': 'sessionStartTime',
      'endTime': 'sessionEndTime',
      'status': 'sessionStatus',
      'subject': 'sessionSubject',
      'hostId': 'hostId',
    };
    return map[sessionField];
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService();
});
