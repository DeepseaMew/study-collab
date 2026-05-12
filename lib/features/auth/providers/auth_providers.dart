import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';

/// Streams Firebase auth state — fires on sign in / sign out.
/// Note: this still emits the user as it was at the moment of sign-in.
/// For live updates to fields like avatar / username / friendsCount,
/// watch [currentUserProvider] instead.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Live AppUser profile from Firestore — null if signed out.
///
/// Streams the user's Firestore document so any change (avatar upload,
/// profile edit, friendsCount/sessionsCount updates from other actions)
/// appears on screen immediately without needing a restart.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (firebaseUser) {
      if (firebaseUser == null) return Stream.value(null);
      return ref.watch(userServiceProvider).watchUser(firebaseUser.id);
    },
    loading: () => Stream.value(null),
    error: (e, _) => Stream.value(null),
  );
});

/// Simple bool — is anyone signed in?
/// Used by the router redirect.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).maybeWhen(
        data: (user) => user != null,
        orElse: () => false,
      );
});