import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/app_user.dart';
import '../models/friend.dart';

/// Friendship status from one user's perspective looking at another.
enum FriendshipStatus {
  self,             // Looking at your own profile
  notFriends,       // No relationship
  requestSent,      // I sent them a request, awaiting response
  requestReceived,  // They sent me a request, awaiting my response
  friends,          // We're friends
}

/// Friend service.
///
/// Data layout:
///   friend_requests/{senderId}_{recipientId}  → request doc (deleted on accept/decline)
///   friends/{ownerId}/userFriends/{friendUserId}  → confirmed friendship (dual docs)
///
/// All friendship state changes use WriteBatch so we never end up with
/// ghost friendships if a write fails midway.
///
/// Denormalized fields cached on Friend docs: username, profilePhotoUrl, bio.
/// When a user updates their profile, all Friend docs that reference them
/// must be updated via a separate fan-out operation (TODO: add to user_service).
class FriendService {
  final FirebaseFirestore _firestore;

  FriendService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Build the deterministic request doc ID.
  String _requestId(String senderId, String recipientId) =>
      '${senderId}_$recipientId';

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Watch the friendship status between two users — live.
  ///
  /// Combines three Firestore listeners and emits the current status whenever
  /// any of them changes.
  Stream<FriendshipStatus> watchFriendshipStatus({
    required String currentUserId,
    required String otherUserId,
  }) {
    if (currentUserId == otherUserId) {
      return Stream.value(FriendshipStatus.self);
    }

    final friendDoc = _firestore
        .collection(FirestoreCollections.friends)
        .doc(currentUserId)
        .collection('userFriends')
        .doc(otherUserId)
        .snapshots();

    final iSentDoc = _firestore
        .collection(FirestoreCollections.friendRequests)
        .doc(_requestId(currentUserId, otherUserId))
        .snapshots();

    final theySentDoc = _firestore
        .collection(FirestoreCollections.friendRequests)
        .doc(_requestId(otherUserId, currentUserId))
        .snapshots();

    return _combineLatest3(friendDoc, iSentDoc, theySentDoc).map((triple) {
      final (friend, iSent, theySent) = triple;
      if (friend.exists) return FriendshipStatus.friends;
      if (iSent.exists) return FriendshipStatus.requestSent;
      if (theySent.exists) return FriendshipStatus.requestReceived;
      return FriendshipStatus.notFriends;
    });
  }

  /// Watch the current user's full friends list — live.
  Stream<List<Friend>> watchFriends(String userId) {
    return _firestore
        .collection(FirestoreCollections.friends)
        .doc(userId)
        .collection('userFriends')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Friend.fromFirestore(d, userId)).toList());
  }

  /// Watch incoming friend requests for [userId] — live.
  /// Used by a "Friend Requests" / notifications screen later.
  Stream<List<FriendRequest>> watchIncomingRequests(String userId) {
    return _firestore
        .collection(FirestoreCollections.friendRequests)
        .where('recipientId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => FriendRequest.fromFirestore(d, userId)).toList());
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// Send a friend request from [fromUser] to [toUser].
  Future<void> sendRequest({
    required AppUser fromUser,
    required AppUser toUser,
  }) async {
    if (fromUser.id == toUser.id) {
      throw DataException('Cannot send a friend request to yourself');
    }

    final docId = _requestId(fromUser.id, toUser.id);
    final ref = _firestore
        .collection(FirestoreCollections.friendRequests)
        .doc(docId);

    try {
      await ref.set({
        'senderId': fromUser.id,
        'recipientId': toUser.id,
        'senderUsername': fromUser.username,
        'senderPhotoUrl': fromUser.profilePhotoUrl,
        'status': FriendRequestStatus.pending.name,
        'sentAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw DataException('Failed to send friend request: $e');
    }
  }

  /// Cancel an outgoing pending request.
  Future<void> cancelRequest({
    required String fromUserId,
    required String toUserId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.friendRequests)
          .doc(_requestId(fromUserId, toUserId))
          .delete();
    } catch (e) {
      throw DataException('Failed to cancel request: $e');
    }
  }

  /// Decline an incoming request without becoming friends.
  Future<void> declineRequest({
    required String fromUserId,
    required String currentUserId,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.friendRequests)
          .doc(_requestId(fromUserId, currentUserId))
          .delete();
    } catch (e) {
      throw DataException('Failed to decline request: $e');
    }
  }

  /// Accept a pending request: deletes the request doc and creates both
  /// friend docs in a single atomic batch.
  Future<void> acceptRequest({
    required AppUser currentUser,
    required AppUser fromUser,
  }) async {
    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    // 1. Delete the pending request.
    batch.delete(_firestore
        .collection(FirestoreCollections.friendRequests)
        .doc(_requestId(fromUser.id, currentUser.id)));

    // 2. Create my view of them (friends/{me}/userFriends/{them}).
    batch.set(
      _firestore
          .collection(FirestoreCollections.friends)
          .doc(currentUser.id)
          .collection('userFriends')
          .doc(fromUser.id),
      {
        'username': fromUser.username,
        'profilePhotoUrl': fromUser.profilePhotoUrl,
        'bio': fromUser.bio,
        'addedAt': now,
      },
    );

    // 3. Create their view of me (friends/{them}/userFriends/{me}).
    batch.set(
      _firestore
          .collection(FirestoreCollections.friends)
          .doc(fromUser.id)
          .collection('userFriends')
          .doc(currentUser.id),
      {
        'username': currentUser.username,
        'profilePhotoUrl': currentUser.profilePhotoUrl,
        'bio': currentUser.bio,
        'addedAt': now,
      },
    );

    // 4. Bump friendsCount on both user docs.
    batch.update(
      _firestore.collection(FirestoreCollections.users).doc(currentUser.id),
      {'friendsCount': FieldValue.increment(1)},
    );
    batch.update(
      _firestore.collection(FirestoreCollections.users).doc(fromUser.id),
      {'friendsCount': FieldValue.increment(1)},
    );

    try {
      await batch.commit();
    } catch (e) {
      throw DataException('Failed to accept request: $e');
    }
  }

  /// Remove an existing friendship — atomic delete of both Friend docs
  /// plus decrement of both friendsCount fields.
  Future<void> unfriend({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final batch = _firestore.batch();

    batch.delete(_firestore
        .collection(FirestoreCollections.friends)
        .doc(currentUserId)
        .collection('userFriends')
        .doc(otherUserId));

    batch.delete(_firestore
        .collection(FirestoreCollections.friends)
        .doc(otherUserId)
        .collection('userFriends')
        .doc(currentUserId));

    batch.update(
      _firestore.collection(FirestoreCollections.users).doc(currentUserId),
      {'friendsCount': FieldValue.increment(-1)},
    );
    batch.update(
      _firestore.collection(FirestoreCollections.users).doc(otherUserId),
      {'friendsCount': FieldValue.increment(-1)},
    );

    try {
      await batch.commit();
    } catch (e) {
      throw DataException('Failed to unfriend: $e');
    }
  }
}

// ── Stream-combining helper ──────────────────────────────────────────────────

/// Combines three streams. Emits whenever any source emits, once all three
/// have emitted at least once.
Stream<(A, B, C)> _combineLatest3<A, B, C>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
) {
  final controller = StreamController<(A, B, C)>();
  A? lastA;
  B? lastB;
  C? lastC;
  var hasA = false, hasB = false, hasC = false;

  void emit() {
    if (hasA && hasB && hasC) {
      controller.add((lastA as A, lastB as B, lastC as C));
    }
  }

  final subA = a.listen((v) {
    lastA = v;
    hasA = true;
    emit();
  }, onError: controller.addError);
  final subB = b.listen((v) {
    lastB = v;
    hasB = true;
    emit();
  }, onError: controller.addError);
  final subC = c.listen((v) {
    lastC = v;
    hasC = true;
    emit();
  }, onError: controller.addError);

  controller.onCancel = () async {
    await subA.cancel();
    await subB.cancel();
    await subC.cancel();
  };

  return controller.stream;
}

// ── Provider ─────────────────────────────────────────────────────────────────

final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService();
});