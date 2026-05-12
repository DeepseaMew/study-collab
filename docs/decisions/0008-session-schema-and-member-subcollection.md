# 0008 — Session schema, member subcollection shape, and participantCount strategy

**Date:** 2026-05
**Status:** Accepted
**Decided by:** Architect agent + human lead

## Problem

`session_service` and `participation_service` are the next implementation
milestone. Before writing a line of service code we need to nail three
interrelated schema questions: what the session doc carries, what the
member subcollection doc must carry for the "My Sessions" screen to render
without joining session data, and how `participantCount` is kept consistent.

## Options considered

### participantCount counter strategy

| Option | Pros | Cons |
|---|---|---|
| **A — Client-side `FieldValue.increment` in the same WriteBatch** (chosen) | Atomic with member doc creation. Zero infra. No billing surprise. Works offline; Firestore queues the write. | If a client crashes between writing the member doc and committing the batch, count drifts. In practice, a batch is all-or-nothing so this is safe. |
| **B — Cloud Function trigger on members write** | Authoritative; no client can fake the count. Consistent even if the client crashes mid-write. | Requires a Cloud Functions deployment. Adds infra complexity and cold-start latency (100–500 ms). Out of scope for a college project. |

### Member doc denormalization

| Option | Pros | Cons |
|---|---|---|
| **Minimal (userId only) + join session doc on read** | Smallest writes. | Every "My Sessions" list load requires a collectionGroup query on members PLUS fetching each session doc — N+1 reads, slower UX. |
| **Full session snapshot cached on member doc** | Single read per card. | Member doc balloons. Session doc changes (title edit, time postpone) must fan out to all member docs — expensive and error-prone. |
| **Card-render fields only on member doc** (chosen) | One collectionGroup query returns enough data to paint the session card without fetching the session doc. Manageable fan-out: only title and startTime/endTime/status need propagating. | Slightly more fields than "minimal"; fan-out on edit required. |

## Decision

Keep the Session doc shape as-is (no structural changes). Use
**Option A** (client-side `FieldValue.increment`) for `participantCount`.
Cache a **card-render subset** on each member doc.

### Session doc — no structural changes

The existing `Session` model fields are correct for Firestore. Two
clarifications:
- `passwordHash` stores `"<sha256hex>:<salt>"` as a single string
  (format decided in ADR 0009). The field stays as `String?`.
- `participantCount` is the count of **approved** members (host + accepted
  participants). Pending requesters are NOT counted.

### Member doc shape (`sessions/{sessionId}/members/{userId}`)

The Participant model already holds `userId`, `sessionId`, `username`,
`profilePhotoUrl`, `role`, `joinedAt`, `attended`. Add these fields
to make a collectionGroup query self-sufficient for a session card:

- `sessionTitle` (String) — copied from `Session.title` at join time.
- `sessionStartTime` (Timestamp) — copied from `Session.startTime`.
- `sessionEndTime` (Timestamp) — copied from `Session.endTime`.
- `sessionStatus` (String) — copied from `Session.status`.
- `sessionSubject` (String) — copied from `Session.subject`.
- `hostId` (String) — needed to route to the host profile.

These six fields must be kept in sync when the host edits title, times,
or cancels/postpones (see ADR 0010 for fan-out rules).

### participantCount update rule

`FieldValue.increment(1)` is written to the session doc in the **same
WriteBatch** that creates the member doc. `FieldValue.increment(-1)` is
in the same batch that deletes it (leave or cancel).

The host member doc is created (and count set to 1) in the same batch
that creates the session doc itself.

## Why we chose these options

Client-side increment (Option A) is standard Firestore practice for
college-scale apps and is already the pattern used for `friendsCount`
in the friend system (ADR 0004). Introducing Cloud Functions just for a
counter would add deployment infrastructure for no correctness gain at
our scale.

The card-render subset on member docs avoids N+1 reads on the most
frequently loaded screen in the app (My Sessions dashboard). The fan-out
cost on edit is bounded: only title, times, and status change, and a batch
can update up to 500 member docs atomically, which exceeds any realistic
session size.

## Reversal cost

**Low for the counter** — switching to a Cloud Function later means
removing the client-side increment and deploying one function; existing
counts stay valid.

**Medium for the member doc shape** — adding or removing cached fields
requires a migration batch over all existing member docs. No user-visible
impact, but a one-time write job.

## Constraints locked in by this decision

- `participantCount` counts **approved members only** (host + joined).
  JoinRequest docs do NOT increment it.
- Every join/leave batch MUST include `FieldValue.increment(±1)` on the
  session doc. Service code must never write a member doc without it.
- Member docs in `sessions/{sessionId}/members/` use `userId` as the doc
  ID (same as Participant model — no change needed).
- When host edits `title`, `startTime`, `endTime`, or `status` on the
  session doc, a fan-out batch also updates those six cached fields on all
  member docs in that session. Max 500 members per batch commit; service
  must handle chunking if needed (unlikely at college scale).
- `sessionsCount` on the user doc (AppUser) is incremented when a user
  becomes a member of any session (host or accepted join). Decremented on
  leave or session cancel.

## See also

- ADR 0004 — `FieldValue.increment` pattern for `friendsCount`.
- ADR 0006 — session visibility (public/private) shapes join flow.
- ADR 0009 — JoinRequest placement and password hashing.
- ADR 0010 — fan-out rules for edit/cancel/postpone.
- `lib/models/participant.dart` — current Participant model (fields to add listed in ADR 0010 work order).
- `docs/firestore-indexes.md` — indexes updated in ADR 0010.
