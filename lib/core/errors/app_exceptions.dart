sealed class AppException implements Exception {
  final String message;
  final String? code;
  const AppException(this.message, {this.code});

  @override
  String toString() => 'AppException($code): $message';
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code});

  factory AuthException.fromFirebaseCode(String code) {
    switch (code) {
      case 'invalid-email':
        return const AuthException('Invalid email address', code: 'invalid-email');
      case 'user-disabled':
        return const AuthException('This account has been disabled', code: 'user-disabled');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return const AuthException('Incorrect email or password', code: 'invalid-credential');
      case 'email-already-in-use':
        return const AuthException('An account with this email already exists', code: 'email-already-in-use');
      case 'weak-password':
        return const AuthException('Password is too weak (minimum 8 characters)', code: 'weak-password');
      case 'network-request-failed':
        return const AuthException('Network error — check your connection', code: 'network-request-failed');
      case 'too-many-requests':
        return const AuthException('Too many attempts. Please try again later', code: 'too-many-requests');
      default:
        return AuthException('Authentication failed', code: code);
    }
  }
}

class DataException extends AppException {
  const DataException(super.message, {super.code});
}

class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code});
}

class PermissionException extends AppException {
  const PermissionException(super.message, {super.code});
}

class StorageException extends AppException {
  const StorageException(super.message, {super.code});
}

class FileTooLargeException extends StorageException {
  const FileTooLargeException(super.message, {super.code});
}

/// Thrown by [AuthService.signUp] when the supplied email address does not
/// belong to an allowed university domain (see [kAllowedEmailDomains]).
class InvalidUniversityEmailException extends AuthException {
  const InvalidUniversityEmailException(super.message)
      : super(code: 'invalid-university-email');
}

/// Thrown by [AuthService.signIn] / [AuthService.authStateChanges] when
/// Firebase Auth succeeds but the corresponding Firestore user document is
/// missing — this should never happen in normal operation but can occur if the
/// Firestore write was rolled back or manually deleted.
class UserProfileNotFoundException extends NotFoundException {
  const UserProfileNotFoundException()
      : super('User profile not found. Please contact support.',
            code: 'user-profile-not-found');
}