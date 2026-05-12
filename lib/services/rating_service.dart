import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/participant.dart';
import '../models/rating.dart';

/// Minimum number of received ratings before a user's score is surfaced in the UI.
const int kMinRatingsForScore = 3;

/// Rating service.
///
/// Firestore paths:
///   ratings/{ratingId}                        ← top-level rating doc
///   users/{userId}                            ← thumbsUpCount / thumbsDownCount / totalRatingsCount incremented here
///   sessions/{sessionId}/members/{userId}     ← read to verify membership
///   sessions/{sessionId}                      ← read to verify endTime
///
/// Denormalized counters on users/{ratedUserId} (incremented atomically):
///   thumbsUpCount    — total thumbs-up ratings received
///   thumbsDownCount  — total thumbs-down ratings received
///   totalRatingsCount — total ratings received (thumbsUp + thumbsDown)
///
/// Deterministic doc ID: {sessionId}_{raterId}_{ratedUserId}
/// This prevents duplicate ratings without a separate query.
class RatingService {
  final FirebaseFirestore _firestore;

  RatingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Builds the deterministic doc ID for a rating.
  static String _ratingId({
    required String sessionId,
    required String raterId,
    required String ratedUserId,
  }) =>
      '${sessionId}_${raterId}_$ratedUserId';

  // ── Writes ───────────────────────────────────────────────────────────────────

  /// Submit a rating from [raterId] to [ratedUserId] for [sessionId].
  ///
  /// Validates (throws [DataException] on failure):
  ///   - rater != ratee
  ///   - session.endTime < now (session must have ended)
  ///   - rater is a confirmed member of the session
  ///   - ratee is a confirmed member of the session
  ///   - no duplicate rating (checked via deterministic doc ID)
  ///
  /// Atomic [WriteBatch]:
  ///   1. CREATE ratings/{deterministicId}
  ///   2. INCREMENT users/{ratedUserId}.thumbsUpCount or thumbsDownCount by 1
  ///   3. INCREMENT users/{ratedUserId}.totalRatingsCount by 1
  Future<void> submitRating({
    required String sessionId,
    required String raterId,
    required String ratedUserId,
    required bool isThumbsUp,
  }) async {
    if (raterId == ratedUserId) {
      throw const DataException('You cannot rate yourself');
    }

    final ratingDocId = _ratingId(
      sessionId: sessionId,
      raterId: raterId,
      ratedUserId: ratedUserId,
    );

    final ratingRef =
        _firestore.collection(FirestoreCollections.ratings).doc(ratingDocId);

    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId);

    final raterMemberRef = sessionRef
        .collection(FirestoreCollections.members)
        .doc(raterId);

    final rateeMemberRef = sessionRef
        .collection(FirestoreCollections.members)
        .doc(ratedUserId);

    final userRef =
        _firestore.collection(FirestoreCollections.users).doc(ratedUserId);

    try {
      // Fetch all required docs in parallel.
      final (sessionSnap, raterMemberSnap, rateeMemberSnap, existingRatingSnap) =
          await (
        sessionRef.get(),
        raterMemberRef.get(),
        rateeMemberRef.get(),
        ratingRef.get(),
      ).wait;

      // Validate: session must exist.
      if (!sessionSnap.exists) {
        throw const DataException('Session not found');
      }

      // Validate: session must have ended.
      final sessionData = sessionSnap.data()!;
      final endTimeRaw = sessionData['endTime'];
      final DateTime endTime;
      if (endTimeRaw is Timestamp) {
        endTime = endTimeRaw.toDate();
      } else {
        throw const DataException('Session end time is missing');
      }
      if (!endTime.isBefore(DateTime.now())) {
        throw const DataException(
            'Ratings can only be submitted after the session has ended');
      }

      // Validate: rater must be a confirmed member.
      if (!raterMemberSnap.exists) {
        throw const DataException(
            'You must be a confirmed member of the session to rate');
      }

      // Validate: ratee must be a confirmed member.
      if (!rateeMemberSnap.exists) {
        throw const DataException(
            'The user you are rating is not a confirmed member of this session');
      }

      // Validate: no duplicate rating.
      if (existingRatingSnap.exists) {
        throw const DataException(
            'You have already rated this member for this session');
      }

      // Build counter increments.
      final Map<String, dynamic> counterIncrements = {
        'totalRatingsCount': FieldValue.increment(1),
      };
      if (isThumbsUp) {
        counterIncrements['thumbsUpCount'] = FieldValue.increment(1);
      } else {
        counterIncrements['thumbsDownCount'] = FieldValue.increment(1);
      }

      // Atomic batch.
      final batch = _firestore.batch();

      // 1. Create rating doc.
      batch.set(ratingRef, {
        'sessionId': sessionId,
        'raterId': raterId,
        'ratedUserId': ratedUserId,
        'isThumbsUp': isThumbsUp,
        'ratedAt': FieldValue.serverTimestamp(),
      });

      // 2 & 3. Increment user counters.
      batch.update(userRef, counterIncrements);

      await batch.commit();

      debugPrint('[rating_service] Rating submitted successfully');
    } catch (e) {
      if (e is DataException) rethrow;
      throw DataException('Failed to submit rating: $e');
    }
  }

  // ── Reads ────────────────────────────────────────────────────────────────────

  /// Returns the existing [Rating] from [raterId] to [ratedUserId] for
  /// [sessionId], or null if no rating exists.
  Future<Rating?> getMyRatingFor({
    required String sessionId,
    required String raterId,
    required String ratedUserId,
  }) async {
    final docId = _ratingId(
      sessionId: sessionId,
      raterId: raterId,
      ratedUserId: ratedUserId,
    );
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.ratings)
          .doc(docId)
          .get();
      if (!doc.exists) return null;
      return Rating.fromFirestore(doc);
    } catch (e) {
      throw DataException('Failed to fetch rating: $e');
    }
  }

  /// Returns true if [userId] has at least [kMinRatingsForScore] ratings.
  Future<bool> hasEnoughRatings(String userId) async {
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .get();
      if (!doc.exists) return false;
      final total = (doc.data()?['totalRatingsCount'] as num?)?.toInt() ?? 0;
      return total >= kMinRatingsForScore;
    } catch (e) {
      throw DataException('Failed to check rating count: $e');
    }
  }

  /// Returns aggregate score data for [userId], or null if the user has fewer
  /// than [kMinRatingsForScore] ratings.
  ///
  /// Record fields:
  ///   - thumbsUp: total positive ratings received
  ///   - thumbsDown: total negative ratings received
  ///   - total: thumbsUp + thumbsDown
  ///   - percentage: (thumbsUp / total * 100), rounded to nearest integer
  Future<({int thumbsUp, int thumbsDown, int total, int percentage})?>
      getScoreFor(String userId) async {
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .get();
      if (!doc.exists) return null;

      final data = doc.data() ?? {};
      final thumbsUp = (data['thumbsUpCount'] as num?)?.toInt() ?? 0;
      final thumbsDown = (data['thumbsDownCount'] as num?)?.toInt() ?? 0;
      final total = (data['totalRatingsCount'] as num?)?.toInt() ?? 0;

      if (total < kMinRatingsForScore) return null;

      final percentage =
          total > 0 ? ((thumbsUp / total) * 100).round() : 0;

      return (
        thumbsUp: thumbsUp,
        thumbsDown: thumbsDown,
        total: total,
        percentage: percentage,
      );
    } catch (e) {
      throw DataException('Failed to fetch score: $e');
    }
  }

  /// Stream of session members the [currentUserId] can still rate.
  ///
  /// Filters out:
  ///   - [currentUserId] themselves
  ///   - Members the current user has already rated for this session
  ///
  /// Returns an empty list immediately if session.endTime > now (session not
  /// yet over — ratings not allowed until the session ends).
  ///
  /// Required composite index on `sessions/{sessionId}/members`:
  ///   (no composite index needed — no orderBy; single-collection scan)
  /// See docs/firestore-indexes.md for ratings collection index.
  Stream<List<Participant>> watchRateableMembers({
    required String sessionId,
    required String currentUserId,
  }) {
    // Start with a one-shot session fetch to check endTime.
    // Then stream the members subcollection and filter asynchronously.
    return Stream.fromFuture(
      _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .get(),
    ).asyncExpand((sessionSnap) {
      if (!sessionSnap.exists) return Stream.value(<Participant>[]);

      final data = sessionSnap.data();
      final endTimeRaw = data?['endTime'];
      if (endTimeRaw is! Timestamp) return Stream.value(<Participant>[]);

      final endTime = endTimeRaw.toDate();
      if (endTime.isAfter(DateTime.now())) {
        // Session hasn't ended yet — no ratings allowed.
        return Stream.value(<Participant>[]);
      }

      // Stream the members subcollection and filter after each emission.
      return _firestore
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .snapshots()
          .asyncMap((membersSnap) async {
        final candidates = membersSnap.docs
            .map((doc) => Participant.fromFirestore(doc, sessionId))
            .where((p) => p.userId != currentUserId)
            .toList();

        if (candidates.isEmpty) return <Participant>[];

        // For each candidate, check if current user already rated them.
        // Use deterministic ID point-reads (no index required).
        final ratingChecks = candidates.map((p) {
          final docId = _ratingId(
            sessionId: sessionId,
            raterId: currentUserId,
            ratedUserId: p.userId,
          );
          return _firestore
              .collection(FirestoreCollections.ratings)
              .doc(docId)
              .get();
        });

        final ratingSnaps = await Future.wait(ratingChecks);

        final rateable = <Participant>[];
        for (var i = 0; i < candidates.length; i++) {
          if (!ratingSnaps[i].exists) {
            rateable.add(candidates[i]);
          }
        }
        return rateable;
      });
    });
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final ratingServiceProvider = Provider<RatingService>(
  (ref) => RatingService(),
);
