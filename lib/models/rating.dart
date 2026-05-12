import 'package:cloud_firestore/cloud_firestore.dart';

/// A thumbs-up or thumbs-down rating given by one session member to another.
///
/// Stored at: ratings/{ratingId}
/// Doc ID is deterministic: {sessionId}_{raterId}_{ratedUserId}
///
/// Denormalized counters are cached on users/{ratedUserId}:
///   thumbsUpCount, thumbsDownCount, totalRatingsCount
/// These must be incremented atomically when a Rating is created
/// (see rating_service.submitRating).
class Rating {
  final String id;
  final String sessionId;
  final String raterId;
  final String ratedUserId;
  final bool isThumbsUp;
  final DateTime ratedAt;

  const Rating({
    required this.id,
    required this.sessionId,
    required this.raterId,
    required this.ratedUserId,
    required this.isThumbsUp,
    required this.ratedAt,
  });

  factory Rating.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception('Rating document ${doc.id} has no data');
    return Rating(
      id: doc.id,
      sessionId: data['sessionId'] as String? ?? '',
      raterId: data['raterId'] as String? ?? '',
      ratedUserId: data['ratedUserId'] as String? ?? '',
      isThumbsUp: data['isThumbsUp'] as bool? ?? true,
      ratedAt: (data['ratedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'raterId': raterId,
      'ratedUserId': ratedUserId,
      'isThumbsUp': isThumbsUp,
      'ratedAt': Timestamp.fromDate(ratedAt),
    };
  }

  Rating copyWith({
    String? sessionId,
    String? raterId,
    String? ratedUserId,
    bool? isThumbsUp,
    DateTime? ratedAt,
  }) {
    return Rating(
      id: id,
      sessionId: sessionId ?? this.sessionId,
      raterId: raterId ?? this.raterId,
      ratedUserId: ratedUserId ?? this.ratedUserId,
      isThumbsUp: isThumbsUp ?? this.isThumbsUp,
      ratedAt: ratedAt ?? this.ratedAt,
    );
  }
}
