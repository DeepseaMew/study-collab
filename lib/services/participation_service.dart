import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/join_request.dart';
import '../models/participant.dart';
import '../models/session.dart';

/// Participation service.
///
/// Firestore paths:
///   sessions/{sessionId}/members/{userId}          ← member docs
///   sessions/{sessionId}/joinRequests/{userId}      ← request docs (doc ID = userId)
///   users/{userId}                                  ← sessionsCount counter
///   users/{userId}/notifications/{autoId}           ← approval/decline notifications
///
/// Rules:
///   - participantCount ALWAYS incremented atomically with member doc creation.
///   - sessionsCount incremented on: host creates (session_service),
///     non-host is approved, non-host joins with password.
///   - sessionsCount decremented on: member leaves.
///
/// Denormalized card-render fields on member docs (ADR 0008):
///   sessionTitle, sessionStartTime, sessionEndTime,
///   sessionStatus, sessionSubject, hostId
/// These are copied from the Session object at join time and are read-only
/// from the participation service's perspective. Updates are the responsibility
/// of session_service (editSession / cancelSession / postponeSession).
class ParticipationService {
  final FirebaseFirestore _firestore;

  ParticipationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Password verification ───────────────────────────────────────────────────

  /// Verify [plainText] against stored [hash] (`"<sha256hex>:<base64salt>"`).
  bool _verifyPassword(String plainText, String hash) {
    final parts = hash.split(':');
    if (parts.length != 2) return false;
    final saltBytes = base64.decode(parts[1]);
    final passwordBytes = utf8.encode(plainText);
    final combined = Uint8List(saltBytes.length + passwordBytes.length)
      ..setRange(0, saltBytes.length, saltBytes)
      ..setRange(
        saltBytes.length,
        saltBytes.length + passwordBytes.length,
        passwordBytes,
      );
    final digest = sha256.convert(combined);
    return digest.toString() == parts[0];
  }

  // ── Reads ───────────────────────────────────────────────────────────────────

  /// Watch all members of [sessionId] in real time.
  Stream<List<Participant>> watchSessionMembers(String sessionId) {
    return _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.members)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Participant.fromFirestore(doc, sessionId))
              .toList(),
        );
  }

  /// Watch all sessions [userId] is a member of, ordered by sessionStartTime DESC.
  ///
  /// Required collection-group index on `members`:
  ///   userId ASC, sessionStartTime DESC
  /// (documented in docs/firestore-indexes.md)
  Stream<List<Participant>> watchUserMemberships(String userId) {
    // collectionGroup query: sessionId is extracted from doc.reference.parent.parent.id
    return _firestore
        .collectionGroup(FirestoreCollections.members)
        .where('userId', isEqualTo: userId)
        .orderBy('sessionStartTime', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final sessionId = doc.reference.parent.parent!.id;
            return Participant.fromFirestore(doc, sessionId);
          }).toList(),
        );
  }

  /// Watch all pending join requests for [sessionId].
  ///
  /// [callerUid] must be the session's hostId — if not, an empty stream is
  /// returned immediately (no Firestore query is issued). This prevents a
  /// non-host from receiving a raw permission-denied error from Firestore.
  ///
  /// Filters by status == 'pending' so declined requests stored for audit
  /// purposes are not surfaced.
  ///
  /// Required composite index on `sessions/{sessionId}/joinRequests`:
  ///   status ASC, requestedAt ASC
  Stream<List<JoinRequest>> watchPendingRequests(
    String sessionId, {
    required String callerUid,
  }) {
    return Stream.fromFuture(
      _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .get(),
    ).asyncExpand((snap) {
      final data = snap.data();
      if (data == null || data['hostId'] != callerUid) {
        return Stream.value(<JoinRequest>[]);
      }
      return _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .where('status', isEqualTo: JoinRequestStatus.pending.name)
          .orderBy('requestedAt')
          .snapshots()
          .map(
            (qs) => qs.docs
                .map((doc) => JoinRequest.fromFirestore(doc, sessionId))
                .toList(),
          );
    });
  }

  /// Watch all pending join requests created by [userId] across all sessions.
  ///
  /// Required collection-group index on `joinRequests`:
  ///   userId ASC, requestedAt DESC
  /// (documented in docs/firestore-indexes.md)
  Stream<List<JoinRequest>> watchMyPendingRequests(String userId) {
    return _firestore
        .collectionGroup(FirestoreCollections.joinRequests)
        .where('userId', isEqualTo: userId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final sessionId = doc.reference.parent.parent!.id;
            return JoinRequest.fromFirestore(doc, sessionId);
          }).toList(),
        );
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  /// Submit a join request for a public session.
  ///
  /// Doc ID = userId (deterministic — prevents duplicate requests).
  /// Throws DataException if a request is already pending.
  Future<void> requestJoin({
    required String sessionId,
    required String userId,
    required String username,
    String? profilePhotoUrl,
  }) async {
    final ref = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.joinRequests)
        .doc(userId);
    try {
      final existing = await ref.get();
      if (existing.exists) {
        throw const DataException('Request already pending for this session');
      }
      await ref.set({
        'userId': userId,
        'username': username,
        'profilePhotoUrl': profilePhotoUrl,
        'status': JoinRequestStatus.pending.name,
        'requestedAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
      });
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to submit join request: $e');
    }
  }

  /// Cancel the user's own pending join request.
  Future<void> cancelJoinRequest({
    required String sessionId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId)
          .delete();
    } catch (e) {
      throw DataException('Failed to cancel join request: $e');
    }
  }

  // Card-render fields on the member doc are sourced from the caller-supplied
  // Session object. If the host edited the session (title/times/status) between
  // request submission and approval, those fields are briefly stale until the
  // session_service.editSession fan-out propagates. This is an accepted trade-off:
  // edit fan-out and approval are independent operations; the stale window is
  // bounded by the time between the edit and the next approval action.
  /// Approve a pending join request (public sessions only).
  ///
  /// Single atomic WriteBatch (ADR 0009):
  ///   1. DELETE sessions/{sessionId}/joinRequests/{requestUserId}
  ///   2. CREATE sessions/{sessionId}/members/{requestUserId} with all fields
  ///   3. INCREMENT sessions/{sessionId}.participantCount by 1
  ///   4. INCREMENT users/{requestUserId}.sessionsCount by 1
  Future<void> approveRequest({
    required Session session,
    required String callerUid,
    required String requestUserId,
    required String requestUsername,
    String? requestUserPhotoUrl,
  }) async {
    // Defense-in-depth on top of Firestore rules.
    if (session.hostId != callerUid) {
      throw const DataException('Only the host can approve requests');
    }

    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(session.id);

    final requestRef = sessionRef
        .collection(FirestoreCollections.joinRequests)
        .doc(requestUserId);

    final memberRef = sessionRef
        .collection(FirestoreCollections.members)
        .doc(requestUserId);

    final userRef = _firestore
        .collection(FirestoreCollections.users)
        .doc(requestUserId);

    final now = FieldValue.serverTimestamp();

    try {
      // Defense-in-depth: verify request doc exists before writing.
      final requestSnap = await requestRef.get();
      if (!requestSnap.exists) {
        throw const DataException('Request no longer exists');
      }

      final batch = _firestore.batch();

      // 1. Delete request doc.
      batch.delete(requestRef);

      // 2. Create member doc.
      batch.set(memberRef, {
        'userId': requestUserId,
        'username': requestUsername,
        'profilePhotoUrl': requestUserPhotoUrl,
        'role': ParticipantRole.member.name,
        'joinedAt': now,
        'attended': false,
        'sessionTitle': session.title,
        'sessionStartTime': Timestamp.fromDate(session.startTime),
        'sessionEndTime': Timestamp.fromDate(session.endTime),
        'sessionStatus': session.status.name,
        'sessionSubject': session.subject.name,
        'hostId': session.hostId,
      });

      // 3. Increment participantCount.
      batch.update(sessionRef, {'participantCount': FieldValue.increment(1)});

      // 4. Increment sessionsCount.
      batch.update(userRef, {'sessionsCount': FieldValue.increment(1)});

      await batch.commit();
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to approve request: $e');
    }
  }

  /// Decline a pending join request — single delete of the request doc.
  ///
  /// [callerUid] must be the session's hostId. Defense-in-depth on top of
  /// Firestore rules — mirrors the authorization check in [approveRequest].
  Future<void> declineRequest({
    required String sessionId,
    required String callerUid,
    required String userId,
  }) async {
    final sessionSnap = await _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .get();
    final data = sessionSnap.data();
    if (data == null) {
      throw const DataException('Session not found');
    }
    if ((data['hostId'] as String?) != callerUid) {
      throw const DataException('Only the host can decline requests');
    }

    try {
      await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId)
          .delete();
    } catch (e) {
      throw DataException('Failed to decline request: $e');
    }
  }

  /// Join a private session using a password.
  ///
  /// Verifies the hash then executes an atomic WriteBatch:
  ///   1. CREATE sessions/{sessionId}/members/{userId}
  ///   2. INCREMENT sessions/{sessionId}.participantCount by 1
  ///   3. INCREMENT users/{userId}.sessionsCount by 1
  ///
  /// NEVER logs plainTextPassword.
  Future<void> joinWithPassword({
    required Session session,
    required String userId,
    required String username,
    String? profilePhotoUrl,
    required String plainTextPassword,
  }) async {
    // Step 1: Verify password.
    if (session.passwordHash == null || session.passwordHash!.isEmpty) {
      throw const DataException('This session has no password set');
    }

    final hashMatches = _verifyPassword(
      plainTextPassword,
      session.passwordHash!,
    );
    if (!hashMatches) {
      throw const DataException('Incorrect password');
    }

    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(session.id);
    final memberRef = sessionRef
        .collection(FirestoreCollections.members)
        .doc(userId);
    final userRef = _firestore
        .collection(FirestoreCollections.users)
        .doc(userId);

    final now = FieldValue.serverTimestamp();

    try {
      final batch = _firestore.batch();

      // 1. Create member doc.
      batch.set(memberRef, {
        'userId': userId,
        'username': username,
        'profilePhotoUrl': profilePhotoUrl,
        'role': ParticipantRole.member.name,
        'joinedAt': now,
        'attended': false,
        'sessionTitle': session.title,
        'sessionStartTime': Timestamp.fromDate(session.startTime),
        'sessionEndTime': Timestamp.fromDate(session.endTime),
        'sessionStatus': session.status.name,
        'sessionSubject': session.subject.name,
        'hostId': session.hostId,
      });

      // 2. Increment participantCount.
      batch.update(sessionRef, {'participantCount': FieldValue.increment(1)});

      // 3. Increment sessionsCount.
      batch.update(userRef, {'sessionsCount': FieldValue.increment(1)});

      await batch.commit();
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to join session: $e');
    }
  }

  /// Leave a session.
  ///
  /// Atomic WriteBatch:
  ///   1. DELETE sessions/{sessionId}/members/{userId}
  ///   2. DECREMENT sessions/{sessionId}.participantCount by 1
  ///   3. DECREMENT users/{userId}.sessionsCount by 1
  Future<void> leaveSession({
    required String sessionId,
    required String userId,
  }) async {
    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId);
    final memberRef = sessionRef
        .collection(FirestoreCollections.members)
        .doc(userId);
    final userRef = _firestore
        .collection(FirestoreCollections.users)
        .doc(userId);

    // Defense-in-depth: hosts must cancel the session instead of leaving.
    final memberSnap = await memberRef.get();
    if (memberSnap.exists &&
        (memberSnap.data()?['role'] as String?) == ParticipantRole.host.name) {
      throw const DataException(
        'Hosts cannot leave their own session. Cancel the session instead.',
      );
    }

    try {
      final batch = _firestore.batch();
      batch.delete(memberRef);
      batch.update(sessionRef, {'participantCount': FieldValue.increment(-1)});
      batch.update(userRef, {'sessionsCount': FieldValue.increment(-1)});
      await batch.commit();
    } catch (e) {
      throw DataException('Failed to leave session: $e');
    }
  }

  /// Mark a member as having attended the session.
  Future<void> markAttended({
    required String sessionId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(userId)
          .update({'attended': true});
    } catch (e) {
      throw DataException('Failed to mark attendance: $e');
    }
  }

  // ── One-shot lookups (used by session_providers to compute myStatus) ─────────

  /// Returns the [Participant] doc for [userId] in [sessionId], or null if
  /// the user is not a member.
  Future<Participant?> getMemberOnce({
    required String sessionId,
    required String userId,
  }) async {
    final doc = await _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.members)
        .doc(userId)
        .get();
    return doc.exists ? Participant.fromFirestore(doc, sessionId) : null;
  }

  /// Returns the [JoinRequest] doc for [userId] in [sessionId], or null if
  /// no request exists.
  Future<JoinRequest?> getJoinRequestOnce({
    required String sessionId,
    required String userId,
  }) async {
    final doc = await _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .collection(FirestoreCollections.joinRequests)
        .doc(userId)
        .get();
    return doc.exists ? JoinRequest.fromFirestore(doc, sessionId) : null;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final participationServiceProvider = Provider<ParticipationService>(
  (ref) => ParticipationService(),
);
