# 0010 — Edit/cancel/postpone semantics, new indexes, and model work order

**Date:** 2026-05
**Status:** Accepted
**Decided by:** Architect agent + human lead

## Problem

Hosting a session generates downstream obligations: if the host edits
their profile (name/photo), edits the session, cancels it, or postpones
it, multiple Firestore documents must change together. We need explicit
rules for each mutation path so `session_service` and
`participation_service` implement the same behavior consistently.

## Options considered

### Profile-change fan-out scope

| Option | Pros | Cons |
|---|---|---|
| **Fan out to session doc + all member docs** (chosen) | Every screen showing session cards or participant lists reflects the current host name and photo. No stale denormalized data. | Fan-out write scales with number of active sessions hosted. Bounded by realistic session count for a KMUTT student (unlikely to exceed a few dozen). |
| **Fan out to session doc only** | Fewer writes. | Participant lists show stale host data (wrong name/photo). Inconsistent with CLAUDE.md rule: "denormalized fields must be updated together." |

### Cancel semantics for pending JoinRequests

| Option | Pros | Cons |
|---|---|---|
| **Delete all pending JoinRequests in the same batch as status change** (chosen) | Clean slate. No orphaned pending docs. Consistent with the delete-on-resolve pattern from ADR 0004/0009. | Batch must include session doc update + all pending request deletes — could approach 500-op limit only if unrealistically many pending requests exist. |
| **Leave pending JoinRequests, rely on status check** | Fewer batch ops. | Requesters see their own request as still "pending" even after session is cancelled. Confusing UX; logic pollution in every JoinRequest-reading query. |

### Postpone notification model

| Option | Pros | Cons |
|---|---|---|
| **In-app notification doc written to `users/{userId}/notifications/{id}` for each member** (chosen) | Consistent with the planned `AppNotification` model. Works without FCM. Members see the change when they next open the app. | Fan-out write to every member's notification subcollection. Same scale concern as profile fan-out — acceptable. |
| **FCM push notification only** | Immediate delivery. | FCM is explicitly "not wired yet" (CLAUDE.md). Blocks session editing on unimplemented infra. |

## Decision

### Host profile-change fan-out

When `user_service.updateProfile` changes `username` or `profilePhotoUrl`,
a batch fan-out updates:

1. All session docs where `hostId == userId` — fields `hostName`,
   `hostPhotoUrl`.
2. All member docs in those sessions — fields `username`,
   `profilePhotoUrl` on the specific host member doc
   (`sessions/{id}/members/{hostId}`).
3. All JoinRequest docs issued from that user are NOT fanned out —
   JoinRequest carries `username` and `profilePhotoUrl` for display in
   the approval list. These docs are short-lived (deleted on resolve) so
   stale display data is acceptable. Add a TODO comment in the service.

### Session field-change fan-out

When the host edits `title`, `startTime`, `endTime`, or `status`:

- Batch updates all member docs in `sessions/{sessionId}/members/` that
  carry the six card-render fields defined in ADR 0008 (`sessionTitle`,
  `sessionStartTime`, `sessionEndTime`, `sessionStatus`, `sessionSubject`,
  `hostId`). Only the changed fields need updating.
- `updatedAt` on the session doc is set to `FieldValue.serverTimestamp()`.

### Cancel (`status → cancelled`)

`session_service.cancelSession` executes a WriteBatch:

1. Update session doc: `status = 'cancelled'`, `updatedAt = serverTimestamp`.
2. Update all member docs' `sessionStatus` field to `'cancelled'`.
3. Delete all pending JoinRequest docs in
   `sessions/{sessionId}/joinRequests/`.
4. Decrement `sessionsCount` on every member's user doc by 1.
   (Host's own count is NOT decremented — the host created the session;
   counting it against them is fair.)
5. Write an in-app notification doc to each member's
   `users/{userId}/notifications/{autoId}` with type `sessionCancelled`,
   payload `{ sessionId, sessionTitle, hostName }`.

Member docs themselves are NOT deleted on cancel — they remain as a
historical record. The `sessionStatus: 'cancelled'` field on the member doc
lets the "My Sessions" screen show cancelled sessions distinctly.

### Postpone (`startTime` moved forward)

`session_service.postponeSession` executes a WriteBatch:

1. Update session doc: `startTime`, `endTime`, `updatedAt`.
2. Update all member docs: `sessionStartTime`, `sessionEndTime`.
3. Pending JoinRequest docs are left untouched — a postpone does not
   invalidate pending requests.
4. Write an in-app notification doc to each member:
   type `sessionPostponed`, payload
   `{ sessionId, sessionTitle, newStartTime }`.

## Why we chose these options

The fan-out-everything approach matches the rule already in CLAUDE.md:
"denormalized fields must be updated together via batch writes." Doing
less would contradict a locked-in project rule.

Deleting pending JoinRequests on cancel mirrors the delete-on-resolve
principle from ADR 0004 and ADR 0009. Orphaned pending requests with
no resolved session are a data-consistency hazard with no upside.

In-app notification docs unblock the UX for cancel/postpone without
requiring FCM infrastructure that isn't wired yet. This is the same
`AppNotification` model already in `lib/models/app_notification.dart`.

## Reversal cost

**Low** — fan-out scope can be widened or narrowed in service code.
Adding FCM later is additive: write the notification doc AND send FCM
push from the same service method (or a Cloud Function listening to the
notification collection).

## Constraints locked in by this decision

- `session_service.cancelSession` MUST atomically cancel JoinRequests +
  decrement member `sessionsCount`. Splitting these into separate writes
  is not allowed.
- Member docs survive session cancellation — `sessionStatus` must be a
  reliable field. The "My Sessions" query should NOT filter out cancelled
  sessions at the query level; the UI decides what to show.
- Notification docs live at `users/{userId}/notifications/{autoId}` —
  auto-generated IDs (there is no deduplication concern; we want one
  notification per event per member).
- JoinRequest docs on a postponed session remain valid. Service MUST NOT
  delete them on postpone.
- Host's `sessionsCount` is decremented only when a session is deleted
  outright, not on cancel. This is a product decision: hosting a cancelled
  session still counts toward "sessions hosted."

---

## New Firestore composite indexes required

The following indexes are needed by `session_service` and
`participation_service` and are not in the current `firestore-indexes.md`.

### 1. Pending join requests for a session (host approval list)
- **Collection:** `sessions/{sessionId}/joinRequests`
- **Fields:** `status` ASC, `requestedAt` ASC
- **Used by:** `participation_service.watchPendingRequests(sessionId)`
- **Why:** filters by `status == 'pending'`, orders by request time.
- **Note:** subcollection, not collection-group — single-collection index.

### 2. User's own pending join requests across all sessions
- **Collection group:** `joinRequests`
- **Fields:** `userId` ASC, `requestedAt` DESC
- **Used by:** `participation_service.watchMyPendingRequests(userId)`
  — "You have N pending join requests" notification badge.
- **Why:** collection-group query by userId.

### 3. Sessions a user has joined, ordered by start time
- **Collection group:** `members`
- **Fields:** `userId` ASC, `sessionStartTime` DESC
- **Used by:** `session_service.watchJoinedSessions(userId)` — My Sessions
  screen ordered chronologically.
- **Why:** extends the existing members collection-group index with an
  ordering field. The current index only declares `userId ASC` with no
  ordering; a second index with `sessionStartTime` is needed for ordered
  queries.

### 4. Upcoming public sessions by subject (filtered browse)
- **Collection:** `sessions`
- **Fields:** `visibility` ASC, `status` ASC, `subject` ASC, `startTime` ASC
- **Used by:** `session_service.browseBySubject(subject)` — subject filter
  in the discover feed.
- **Why:** the existing discover-feed index covers `visibility + status +
  startTime`; adding `subject` requires a separate index.

---

## Model work order for firebase-specialist

This is the authoritative handoff list. No model changes exist until
firebase-specialist implements them.

### `lib/models/participant.dart` — ADD six fields

Driven by ADR 0008 (card-render subset):

| Field | Type | Notes |
|---|---|---|
| `sessionTitle` | `String` | Copied from Session.title at join time |
| `sessionStartTime` | `DateTime` | Copied from Session.startTime |
| `sessionEndTime` | `DateTime` | Copied from Session.endTime |
| `sessionStatus` | `SessionStatus` | Copied from Session.status; updated on cancel/postpone |
| `sessionSubject` | `Subject` | Copied from Session.subject |
| `hostId` | `String` | Copied from Session.hostId |

All six fields must appear in `fromFirestore`, `toFirestore`, and
`copyWith`. `sessionStatus` and `sessionSubject` use their existing
`fromString` safe-default methods.

### `lib/models/session.dart` — NO structural changes

The Session doc shape is confirmed correct as-is (ADR 0008).
One implementation note only: `passwordHash` stores the combined
`"<sha256hex>:<base64salt>"` string — the model field is `String?` which
is already correct.

### `lib/models/join_request.dart` — NO structural changes

The doc path changes (subcollection — ADR 0009) but the model fields are
unchanged. The `sessionId` field on the model is populated by the service
from the parent path, same as `Participant.sessionId`.

### NEW: no new model files required

`AppNotification` (`lib/models/app_notification.dart`) already exists in
the codebase. No new model is needed for cancel/postpone notifications —
use the existing model with notification types `sessionCancelled` and
`sessionPostponed`.

---

## Handoff callouts

- **firebase-specialist** — Implement `session_service.dart` and
  `participation_service.dart` per the service interface described across
  ADRs 0008–0010. Add the six fields to `Participant`. Update
  `FirestoreCollections` if any new collection-group names are needed.
  Add the four new composite indexes to `docs/firestore-indexes.md` and
  Firebase Console.

- **security-reviewer** — Review the password hashing approach in ADR 0009
  (client-side SHA-256 + per-session salt). Confirm that storing
  `"<sha256hex>:<base64salt>"` in the session doc is acceptable under the
  project threat model. Confirm Firestore rules will restrict
  `passwordHash` reads to the host only (the field must not be readable by
  non-participants querying the browse feed).

- **qa-engineer** — Test plan should cover:
  - `participantCount` consistency: join, leave, decline, cancel all keep
    the count correct.
  - Password verification: correct password admits, wrong password throws
    `DataException`.
  - Approval batch atomicity: mid-batch failure leaves no orphaned member
    doc without a count increment.
  - Cancel fan-out: all pending JoinRequests deleted, all member
    `sessionsCount` decremented, notification docs written.
  - Postpone fan-out: member docs updated, JoinRequests untouched.

## See also

- ADR 0004 — delete-on-resolve pattern (reused for JoinRequests).
- ADR 0006 — session visibility (drives which join path triggers).
- ADR 0007 — rating system depends on session completion and attendance
  marks; `attended` field on Participant is the dependency.
- ADR 0008 — member doc shape (six card-render fields).
- ADR 0009 — JoinRequest placement and password hashing.
- `lib/models/app_notification.dart` — existing notification model.
- `docs/firestore-indexes.md` — must be updated with the four new indexes.
