# 0015 — Friendship enforcement for direct messages

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

DMs must be restricted to confirmed friends. The app must prevent:
(a) creating a new DM with a non-friend, and
(b) accessing an existing DM after the friendship is dissolved.

Two enforcement layers exist: service-layer code and Firestore rules.
We need to decide how each layer enforces the friend requirement, and
what happens to an existing conversation if the two users unfriend.

## Options considered

### Enforcement mechanism

| Option | Pros | Cons |
|---|---|---|
| **A. Service-layer guard + Firestore rules cross-collection `exists()` check** | Defense in depth. Service check gives a good error message before a network round trip. Rules catch any client bypassing the service. | Rules `exists()` call on `friends/{uid}/userFriends/{otherUid}` costs one extra read per rule evaluation. At DM-send frequency, this is negligible. |
| **B. Service-layer guard only — rules rely on `participantIds`** | Simpler rules. | A determined client can write directly to Firestore and bypass the friendship gate without any rule enforcement. |
| **C. Denormalize friendship into the conversation doc** | Rules need no cross-collection check. | Friendship state on the conversation doc goes stale when users unfriend. Requires a fan-out from `unfriend` to patch `isActive` on the conversation doc. |

### Unfriend behaviour on existing conversation

| Option | Pros | Cons |
|---|---|---|
| **Soft lock — conversation doc stays; rules block new messages but history remains readable** | History is preserved. Simple — no cleanup batch on unfriend. | Former friends can still read each other's old messages. Acceptable for a study-session app; no PII beyond chat text. |
| **Hard delete — `unfriend` batch deletes the conversation doc and all messages** (considered but rejected) | Clean break; no residual data. | Deleting subcollection messages from the client requires fetching all message docs first — expensive batch that could hit the 500-op limit. Adds complexity to an already-batched `unfriend` operation. |

## Decision

Enforce friendship in **both** layers:

1. **Service layer**: before creating or sending to a DM, `chat_service`
   reads `friends/{currentUid}/userFriends/{otherUid}` and throws
   `DataException('You must be friends to message this user')` if it does
   not exist.

2. **Firestore rules**: DM `create` and message `create` both require that
   `exists(/databases/$(database)/documents/friends/$(request.auth.uid)/userFriends/$(otherUid))`.
   The `otherUid` is derived from `participantIds` on the conversation doc.

3. **On unfriend**: the conversation doc and messages are **not deleted**.
   The Firestore rule for message `create` re-evaluates friendship at write
   time, so former friends cannot send new messages. They can still read
   history. No fan-out or cleanup is needed in the `unfriend` batch.

### Why the soft lock on unfriend is correct

The `unfriend` operation already executes a 4-write batch (ADR 0004 /
`friend_service.unfriend`). Adding a message-deletion fan-out would require
fetching all message docs — potentially hundreds of reads — and could
exceed the 500-write-per-batch limit. This cost is disproportionate to the
benefit (preventing two ex-friends from reading a shared chat history that
they both participated in creating). The soft lock is consistent with how
most consumer chat apps handle this case.

## Reversal cost

**Low for service-layer guard** — add or remove the check in one method.

**Low for rules check** — add or remove the `exists()` call in the DM
rules block.

**Medium for unfriend hard-delete** — adding deletion requires a chunked
batch in `friend_service.unfriend` plus permission to query the messages
subcollection. This would be a meaningful change to an otherwise simple
service method.

## Constraints locked in by this decision

- `chat_service.openOrCreateDm` MUST check friendship before writing the
  conversation doc. Throw `DataException` if not friends.
- `chat_service.sendDmMessage` MUST NOT bypass the service-layer guard
  (even if the conversation doc already exists — guard must run on every
  message send, not just on conversation creation).
- Firestore rules for `chats/{dmId}` and `chats/{dmId}/messages/{messageId}`
  MUST include the `exists()` friendship check on `create` (ADR 0016).
- `friend_service.unfriend` does NOT need to be amended to handle chat
  cleanup. This is a locked product decision for v1.
- Future note (flagged, not designed): if message deletion on unfriend
  becomes a requirement, it belongs in a Cloud Function triggered by the
  `friends` deletion, not in the client batch.

## See also

- ADR 0003 — deterministic IDs for friend docs (path used in the `exists()`
  check: `friends/{uid}/userFriends/{otherUid}`).
- ADR 0004 — `unfriend` atomic batch (not amended by this ADR).
- ADR 0012 — DM conversation doc schema and `participantIds` array.
- ADR 0016 — Firestore security rules (implements the `exists()` guard).
- `lib/services/friend_service.dart` — `unfriend` method, `watchFriendshipStatus`.
