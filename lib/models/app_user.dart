import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String email;
  final String username;
  final String bio;
  final String? profilePhotoUrl;
  final int friendsCount;
  final int sessionsCount;
  final double averageRating;
  final int reviewCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    this.bio = '',
    this.profilePhotoUrl,
    this.friendsCount = 0,
    this.sessionsCount = 0,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception('User document ${doc.id} has no data');
    return AppUser(
      id: doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      friendsCount: data['friendsCount'] as int? ?? 0,
      sessionsCount: data['sessionsCount'] as int? ?? 0,
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: data['reviewCount'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'username': username,
      'bio': bio,
      'profilePhotoUrl': profilePhotoUrl,
      'friendsCount': friendsCount,
      'sessionsCount': sessionsCount,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AppUser copyWith({
    String? email,
    String? username,
    String? bio,
    String? profilePhotoUrl,
    int? friendsCount,
    int? sessionsCount,
    double? averageRating,
    int? reviewCount,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id,
      email: email ?? this.email,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      friendsCount: friendsCount ?? this.friendsCount,
      sessionsCount: sessionsCount ?? this.sessionsCount,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}