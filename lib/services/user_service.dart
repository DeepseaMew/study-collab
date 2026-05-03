import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/app_user.dart';

class UserService {
  final FirebaseFirestore _firestore;

  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Get a user profile by ID — one time read
  Future<AppUser?> getUser(String userId) async {
    try {
      final doc = await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .get();

      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    } catch (e) {
      throw DataException('Failed to fetch user: $e');
    }
  }

  /// Watch a user profile in real time — for profile screens
  Stream<AppUser?> watchUser(String userId) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  /// Update username and/or bio
  Future<void> updateProfile({
    required String userId,
    String? username,
    String? bio,
    String? profilePhotoUrl,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (username != null) updates['username'] = username.trim();
      if (bio != null) updates['bio'] = bio;
      if (profilePhotoUrl != null) updates['profilePhotoUrl'] = profilePhotoUrl;

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(userId)
          .update(updates);
    } catch (e) {
      throw DataException('Failed to update profile: $e');
    }
  }

  /// Check if a username is already taken
  Future<bool> isUsernameTaken(String username) async {
    try {
      final query = await _firestore
          .collection(FirestoreCollections.users)
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      throw DataException('Failed to check username: $e');
    }
  }

  /// Search users by username — for the add friend / find user feature
  Future<List<AppUser>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      // Firestore doesn't support full-text search natively.
      // This does a prefix match: "mew" matches "mew", "mewsomething"
      final snapshot = await _firestore
          .collection(FirestoreCollections.users)
          .where('username', isGreaterThanOrEqualTo: query.trim())
          .where('username', isLessThanOrEqualTo: '${query.trim()}\uf8ff')
          .limit(20)
          .get();

      return snapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList();
    } catch (e) {
      throw DataException('Failed to search users: $e');
    }
  }
}

final userServiceProvider = Provider<UserService>((ref) {
  return UserService();
});