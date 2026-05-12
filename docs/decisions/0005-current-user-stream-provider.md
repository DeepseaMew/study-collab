# 0005 — currentUserProvider: StreamProvider, not FutureProvider

**Date:** 2026-05 (decided retroactively, recorded after the fact)
**Status:** Accepted
**Decided by:** flutter-engineer + human lead

## Problem

The router and most screens need to know "who is the currently logged-in
user?" — typed as `AsyncValue<AppUser?>`. The original implementation in
`auth_providers.dart` used a `FutureProvider`, which fetches the user
once and caches the result.

This caused a real bug: after a user edited their profile (changed name,
uploaded avatar), the screen kept showing the cached old data until the
app was fully restarted. Same issue would affect any field that changes
elsewhere — `friendsCount` going up after accepting a friend request,
`sessionsCount` after joining a session, etc.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **Keep FutureProvider**, manually `ref.invalidate(currentUserProvider)` after every write that touches the user doc. | No infrastructure change. | Every write site has to remember to invalidate. Forgetting one introduces a stale-data bug. Doesn't pick up changes made on another device. |
| **Switch to StreamProvider** that watches the user's Firestore document live (chosen). | One change, fixes the entire class of bug. Picks up changes from any source automatically — our writes, other devices, server-side updates. | Keeps a Firestore listener open while a user is signed in (small but ongoing read cost). Slightly more complex provider definition. |

## Decision

Replace `currentUserProvider` with a `StreamProvider` that watches
`users/{uid}` via `userService.watchUser`. When auth state changes
(signed in / signed out / different user), the stream automatically
re-targets via `ref.watch(authStateProvider)`.

```dart
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
```

Consumers don't change — `ref.watch(currentUserProvider)` returns
`AsyncValue<AppUser?>` either way. Riverpod gets the type right
regardless of whether the underlying provider is a Future or Stream.

## Why we chose StreamProvider

The bug class isn't a one-off — it would recur every time the user doc's
fields change anywhere in the app. Solving it with manual invalidation
means every future write site must remember the rule. Solving it with a
stream is a single change that prevents the entire class.

The runtime cost (one open listener per signed-in user) is negligible
for a college-scale app. Firestore charges per document read, not per
listener-second. The listener only fires when the doc actually changes.

## Reversal cost

**Low.** Going back to FutureProvider is a small code change. The bigger
effort would be re-instituting manual `ref.invalidate(...)` calls at
every write site that touches the user doc — a project-wide grep job.

## Constraints locked in by this decision

- Service-side fan-out: when a user updates their profile (username or
  photoUrl), all denormalized copies (Friend docs, Session.hostName,
  etc.) must be updated atomically via batch — otherwise the live
  stream will show inconsistent data across screens. Already handled
  in `user_service.updateProfile` (when the fan-out logic is added).
- The verify-email screen calls `ref.invalidate(currentUserProvider)`
  after the user clicks "I've verified" — needed because email
  verification status lives on the Firebase Auth user object, not the
  Firestore user doc. The stream fires on Firestore changes, not on
  Auth changes; the invalidate triggers the full re-evaluation.

## See also
- `lib/features/auth/providers/auth_providers.dart` — provider definition.
- `lib/services/user_service.dart` — `watchUser` method.
- `lib/features/auth/screens/verify_email_screen.dart` — the
  invalidate-after-verify pattern.
