# 0004 — Friend request lifecycle: delete on accept/decline

**Date:** 2026-05 (decided retroactively, recorded after the fact)
**Status:** Accepted
**Decided by:** firebase-specialist + human lead

## Problem

When user B accepts or declines a friend request from user A, what
happens to the request doc?

The existing `FriendRequest` model has a `status` enum with three values
(`pending`, `accepted`, `declined`) plus a `respondedAt` field. This
suggests the original author intended to keep the doc around with its
status mutated. We needed to confirm or reverse that intent.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **Keep doc, update status** to `accepted`/`declined`, fill in `respondedAt`. | History trail of past requests. Could power a "X accepted your request 2 days ago" notification feed. Matches model's existing field shape. | Every "is there a pending request?" check has to filter by `status == pending`. Docs accumulate forever. Profile views pay the filtering cost on every load. |
| **Delete the doc** when accepted or declined (chosen). | Doc existence = pending. Simplest possible status check. No accumulation. | No history of past requests anywhere. If A is repeatedly declined by B, there's no record. The `status` and `respondedAt` fields on the model become unused. |

## Decision

**Delete the request doc** when the recipient accepts or declines.

On accept, the same `WriteBatch` that creates the two friend docs also
deletes the request doc. On decline, just the delete. No status mutation.

The `status` and `respondedAt` fields on `FriendRequest` are kept on the
model for now (no harm in unused fields) but never written by the service
in the new design. They will only ever read as `pending` — which is
correct, since deleted docs aren't read at all.

## Why we chose delete

We don't have a notifications history feature in our roadmap. We don't
plan to surface "X declined your request last week" anywhere in the UI.
For Study Collab's actual feature set, the historical data has no
consumer.

Meanwhile, the runtime cost of "filter by status == pending" is paid on
every profile view (combined with ADR 0003's friendship-status stream).
Multiplied across users, that's real cost for data nobody reads.

The simpler design wins on every dimension that matters:
- Faster reads (existence check, no filter).
- Cheaper writes (one delete vs one update).
- Simpler queries (no `where('status', isEqualTo: 'pending')` clause).
- Smaller collection over time.

## Reversal cost

**Low.** If we add a notifications history feature later and need request
history, we can:
1. Switch service methods from `delete` to `update({status, respondedAt})`.
2. Add the history query.
3. Old already-deleted requests won't appear in history — acceptable, the
   feature starts from when it ships.

A few hours of code change. No data migration needed.

## Constraints locked in by this decision

- The `status` field on `FriendRequest` model is effectively always
  `pending`. Don't add code that branches on `status == accepted`.
- The "Friend Requests" notification screen (when built) queries
  `friendRequests` directly — every doc that exists is pending, no
  filtering needed.
- Re-sending a declined request: since the previous declined doc is
  gone, the sender CAN send again. This is the intended UX. If we
  want to prevent re-sends from declined-by users, we'd need a
  separate "blocks" or "decline-history" mechanism — out of scope.

## See also
- `lib/services/friend_service.dart` — `acceptRequest`, `declineRequest`,
  `cancelRequest` all use `delete` (no status mutation).
- `lib/models/friend.dart` — the `FriendRequest` model (status field
  retained but unused in writes).
- ADR 0003 — deterministic doc IDs make the existence check cheap;
  this ADR makes the existence check meaningful.
