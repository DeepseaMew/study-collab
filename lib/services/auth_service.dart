import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/auth_constants.dart';
import '../core/constants/firestore_collections.dart';
import '../core/errors/app_exceptions.dart';
import '../models/app_user.dart';
import '../models/enums.dart';

/// AuthService handles Firebase Auth operations and the corresponding
/// Firestore user document.
///
/// PII policy: this service never logs full email addresses, passwords,
/// or session passwords. Log messages use only the uid when an identifier
/// is needed.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Auth-state stream
  // ---------------------------------------------------------------------------

  /// Emits the [AppUser] whenever the signed-in user changes, or null when the
  /// user signs out.
  ///
  /// If Firestore returns an error while fetching the profile the stream emits
  /// null and logs the error (without PII).
  Stream<AppUser?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      try {
        return await _fetchUserProfile(firebaseUser.uid);
      } on UserProfileNotFoundException {
        // Profile missing — treat as signed out so the UI can handle it.
        return null;
      } on AppException catch (e) {
        // Log the error code, never the uid or PII directly in a message.
        debugPrint('[AuthService] authStateChanges error: ${e.code} — ${e.message}');
        return null;
      } catch (e) {
        debugPrint('[AuthService] authStateChanges unexpected error: $e');
        return null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Sign up
  // ---------------------------------------------------------------------------

  /// Creates a new Firebase Auth account and a matching Firestore user document.
  ///
  /// Throws:
  /// - [InvalidUniversityEmailException] if [email] is not a university address.
  /// - [AuthException] for any Firebase Auth failure.
  /// - [DataException] if the Firestore write fails (Auth user is rolled back).
  ///
  /// On any post-Auth failure the Firebase Auth user is deleted before
  /// re-throwing, so there are no orphaned Auth accounts.  Note: if the
  /// rollback itself fails, an orphaned Firebase Auth account may remain.
  /// See [_tryDeleteAuthUser] for details.
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
    required AcademicLevel academicLevel,
    required int studentYear,
    required String faculty,
  }) async {
    // 1. Validate email domain.
    if (!isAllowedUniversityEmail(email)) {
      throw InvalidUniversityEmailException(
        'Only university email addresses are accepted '
        '(${kAllowedEmailDomains.join(", ")}).',
      );
    }

    // 2. Validate student year range.
    final maxYear = AppUser.maxYearFor(academicLevel);
    if (studentYear < 1 || studentYear > maxYear) {
      throw AuthException(
        'Student year must be between 1 and $maxYear '
        'for ${academicLevel.displayName} students.',
        code: 'invalid-student-year',
      );
    }

    // All validation above is done before the try block.  The try block only
    // covers Firebase I/O so every caught exception here originates from Auth
    // or Firestore — not from the validation guards above.
    UserCredential? credential;
    AppUser? newUser;
    try {
      // 3. Create Firebase Auth account.
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      // 4. Write Firestore user document using server timestamps.
      //    createdAt/updatedAt are supplied explicitly via
      //    FieldValue.serverTimestamp() to keep the timestamp authoritative
      //    and consistent across clients.
      final docData = <String, dynamic>{
        'email': email.trim(),
        'username': username.trim(),
        'bio': '',
        'profilePhotoUrl': null,
        'academicLevel': academicLevel.name,
        'studentYear': studentYear,
        'faculty': faculty.trim(),
        'friendsCount': 0,
        'sessionsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .set(docData);

      // 5. Build the AppUser.  Because server timestamps are not readable back
      //    from the write result, we use DateTime.now() locally.  The
      //    authoritative value lives in Firestore and will be read on next
      //    profile fetch.
      final now = DateTime.now();
      newUser = AppUser(
        id: uid,
        email: email.trim(),
        username: username.trim(),
        academicLevel: academicLevel,
        studentYear: studentYear,
        faculty: faculty.trim(),
        createdAt: now,
        updatedAt: now,
      );
    } on FirebaseAuthException catch (e) {
      // Roll back: no Auth user created yet if this path is reached, but guard
      // anyway in case createUserWithEmailAndPassword partially succeeded.
      await _tryDeleteAuthUser(credential);
      throw AuthException.fromFirebaseCode(e.code);
    } catch (e) {
      // Firestore write failed — roll back Auth user.
      await _tryDeleteAuthUser(credential);
      throw DataException(
        'Account created but profile could not be saved. Please try again.',
        code: 'profile-write-failed',
      );
    }

    // 6. Update Firebase Auth display name — best-effort; in its own isolated
    //    try/catch AFTER the main block so a failure here never triggers Auth
    //    rollback after a successful Firestore write.
    try {
      await credential.user!.updateDisplayName(username.trim());
    } catch (_) {
      // best-effort; display name is not critical
    }

    return newUser;
  }

  // ---------------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------------

  /// Signs in with [email] and [password], then loads the Firestore profile.
  ///
  /// Throws:
  /// - [AuthException] for any Firebase Auth failure.
  /// - [UserProfileNotFoundException] if the Firestore doc is missing.
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
    } on UserProfileNotFoundException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code);
    } on AppException {
      rethrow;
    } catch (e) {
      throw const AuthException('Sign in failed. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code);
    }
  }

  // ---------------------------------------------------------------------------
  // Current user (one-shot)
  // ---------------------------------------------------------------------------

  User? get currentFirebaseUser => _auth.currentUser;

  /// Returns the signed-in [AppUser], or null if nobody is signed in or the
  /// Firestore document is missing.
  Future<AppUser?> getCurrentAppUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    try {
      return await _fetchUserProfile(firebaseUser.uid);
    } on UserProfileNotFoundException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<AppUser> _fetchUserProfile(String uid) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .get();

    if (!doc.exists) throw const UserProfileNotFoundException();

    return AppUser.fromFirestore(doc);
  }

  /// Attempts to delete the Firebase Auth user created during a failed signUp.
  ///
  /// If the deletion fails, the uid is logged (non-PII — no email or password)
  /// so the orphaned account can be found and cleaned up manually.  Callers
  /// should not assume this always succeeds — an orphaned Firebase Auth account
  /// is possible when this throws.
  Future<void> _tryDeleteAuthUser(UserCredential? credential) async {
    if (credential?.user == null) return;
    try {
      await credential!.user!.delete();
    } catch (e) {
      // Log uid only — never log email or password.
      debugPrint(
        '[AuthService] WARN: rollback delete failed for uid: '
        '${credential!.user!.uid} — $e',
      );
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});
