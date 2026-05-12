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
        return null;
      } on AppException catch (e) {
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
  /// Required: email, password, username.
  /// Optional: academicLevel, studentYear, faculty — fall back to defaults
  ///           (undergraduate / 1 / '') and can be edited later from profile.
  ///
  /// Throws:
  /// - [InvalidUniversityEmailException] if [email] is not a university address
  ///   (currently disabled — see auth_constants for status).
  /// - [AuthException] for any Firebase Auth failure.
  /// - [DataException] if the Firestore write fails (Auth user is rolled back).
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
    AcademicLevel academicLevel = AcademicLevel.undergraduate,
    int studentYear = 1,
    String faculty = '',
  }) async {

    if (!isAllowedUniversityEmail(email)) {
    throw InvalidUniversityEmailException(
    'Only university email addresses are accepted '
    '(${kAllowedEmailDomains.join(", ")}).',
    );
    }

    UserCredential? credential;
    AppUser? newUser;
    try {
      // 2. Create Firebase Auth account.
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      // 3. Write Firestore user document using server timestamps.
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

      // 4. Build the AppUser locally. Server timestamps aren't readable from
      //    the write result — authoritative values live in Firestore.
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
      await _tryDeleteAuthUser(credential);
      throw AuthException.fromFirebaseCode(e.code);
    } catch (e) {
      await _tryDeleteAuthUser(credential);
      throw DataException(
        'Account created but profile could not be saved. Please try again.',
        code: 'profile-write-failed',
      );
    }

    // 5. Update Firebase Auth display name — best-effort, isolated try/catch.
    try {
      await credential.user!.updateDisplayName(username.trim());
    } catch (_) {
      // best-effort; display name is not critical
    }
    // 6. Send email verification link — best-effort.
try {
  await credential.user!.sendEmailVerification();
} catch (e) {
  debugPrint('[AuthService] sendEmailVerification failed: $e');
  // best-effort; user can resend from the verify screen
}

    return newUser;
  }

  // ---------------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------------

  /// Signs in with [email] and [password], then loads the Firestore profile.
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
// Email verification
// ---------------------------------------------------------------------------

/// Returns true if the current user's email is verified.
///
/// Reloads the user from Firebase first so we pick up the latest status —
/// the local cache won't update on its own when the user clicks the link
/// in their inbox.
Future<bool> isEmailVerified() async {
  final user = _auth.currentUser;
  if (user == null) return false;
  try {
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  } catch (e) {
    debugPrint('[AuthService] isEmailVerified reload failed: $e');
    return user.emailVerified;
  }
}

/// Resend the verification email to the current user.
/// Throws AuthException if Firebase rate-limits us or fails for any reason.
Future<void> resendVerificationEmail() async {
  final user = _auth.currentUser;
  if (user == null) {
    throw const AuthException('Not signed in');
  }
  try {
    await user.sendEmailVerification();
  } on FirebaseAuthException catch (e) {
    throw AuthException.fromFirebaseCode(e.code);
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

  Future<void> _tryDeleteAuthUser(UserCredential? credential) async {
    if (credential?.user == null) return;
    try {
      await credential!.user!.delete();
    } catch (e) {
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
