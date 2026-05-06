
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import '../../../services/auth_service.dart';

/// Streams Firebase auth state — fires on sign in / sign out
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Full AppUser profile from Firestore — null if signed out
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (firebaseUser) async {
      if (firebaseUser == null) return null;
      return ref.read(authServiceProvider).getCurrentAppUser();
    },
    loading: () => null,
    error: (e, _) => null,
  );
});

/// Simple bool — is anyone signed in?
/// Used by the router redirect
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).maybeWhen(
    data: (user) => user != null,
    orElse: () => false,
  );
});