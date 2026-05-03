import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/app_user.dart';

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  User? get currentFirebaseUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;
      final now = DateTime.now();

      final appUser = AppUser(
        id: uid,
        email: email.trim(),
        username: username.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .set(appUser.toFirestore());

      await credential.user!.updateDisplayName(username.trim());

      return appUser;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code);
    } catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }
      throw const AuthException('Failed to create account. Please try again.');
    }
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return await _fetchUserProfile(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code);
    }
  }

  Future<AppUser> _fetchUserProfile(String uid) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .get();

    if (!doc.exists) throw const NotFoundException('User profile not found');

    return AppUser.fromFirestore(doc);
  }

  Future<AppUser?> getCurrentAppUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    try {
      return await _fetchUserProfile(firebaseUser.uid);
    } on NotFoundException {
      return null;
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});