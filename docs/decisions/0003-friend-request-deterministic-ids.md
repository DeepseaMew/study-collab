# 0003 — Friend request doc IDs: deterministic, not random

**Date:** 2026-05 (decided retroactively, recorded after the fact)
**Status:** Accepted
**Decided by:** firebase-specialist + human lead

## Problem

Friend requests live in the `friendRequests` collection. We needed to pick
how each doc is identified.

The screen showing another user's profile asks Firestore three questions
on every page load: "did I send them a request?", "did they send me one?",
and "are we already friends?". The doc ID strategy determines whether
those are cheap point reads or expensive collection queries.

The existing `FriendRequest` model already has its own `id` field —
suggesting the original author was leaning toward random IDs in a flat
collection. But the model doesn't enforce one or the other; the `id`
field just stores whatever ID Firestore gives the doc.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **Random IDs** (Firestore auto-generated): `friendRequests/{autoId}` with `senderId`/`recipientId` fields. | Matches author intent. No collisions. | "Did A send B a request?" requires a query (`where senderId == A AND recipientId == B`), not a point read. Slower, more expensive. |
| **Deterministic IDs**: `friendRequests/{senderId}_{recipientId}` (chosen). | Every status check is a single point read. Doc existence = pending request. Trivial duplicate prevention. | Composite ID is opaque in the console. "Self-friend" requests must be rejected in service code (since `A_A` would be a valid ID). |

## Decision

Use deterministic IDs in the format `{senderId}_{recipientId}`.

The friend-status stream watches three docs by ID and combines them:
- `friends/{me}/userFriends/{them}` — are we already friends?
- `friendRequests/{me}_{them}` — did I send them a request?
- `friendRequests/{them}_{me}` — did they send me one?

Three point reads. No queries. Live updates via three combined snapshot
listeners. See `friend_service.watchFriendshipStatus`.

## Why we chose deterministic

The "view a profile" path runs constantly in the app — every time someone
opens any other user's profile screen. Profile views must be fast and
cheap. Point reads are an order of magnitude faster and cheaper than
queries, and Firestore charges per query but not per point read.

The tradeoff (less natural-looking doc IDs in the Firebase Console) is
purely a developer-experience cost, not a runtime cost. We chose runtime.

## Reversal cost

**Medium.** Switching to random IDs would require:
1. Migrating existing friendRequest docs to new auto-generated IDs.
2. Adding composite indexes for the `(senderId, recipientId)` query.
3. Rewriting `watchFriendshipStatus` to use queries instead of point reads.
4. Accepting the per-load query cost on every profile view.

A few hours of code change plus a one-time data migration.

## Constraints locked in by this decision

- Service code MUST reject `sendRequest(fromUser: x, toUser: x)` —
  otherwise `x_x` would be a valid pending self-request. Already
  enforced in `friend_service.sendRequest`.
- Doc IDs contain user UIDs — must not be displayed in any user-facing
  URL or logged in plaintext (UIDs are not super-sensitive but they're
  not for users to see either).

## See also
- `lib/services/friend_service.dart` — `_requestId` helper, all
  request methods.
- ADR 0004 (next) — friend request lifecycle: delete on accept,
  not status-update. Both decisions interact: deterministic IDs make
  the "is there a pending request?" check trivial *because* request
  docs only exist while pending.
