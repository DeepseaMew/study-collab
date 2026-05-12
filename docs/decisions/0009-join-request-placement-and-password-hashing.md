# 0009 — JoinRequest placement, approval batch, and private-session password hashing

**Date:** 2026-05
**Status:** Accepted
**Decided by:** Architect agent + human lead

## Problem

Two interrelated decisions must be made before `participation_service`
can be written:

1. Where do JoinRequest docs live, and what does the atomic approval
   batch look like?
2. How are private session passwords hashed and verified, given that
   CLAUDE.md mandates SHA-256 + per-session salt via the `crypto` package?

## Options considered

### JoinRequest placement

| Option | Pros | Cons |
|---|---|---|
| **Subcollection under session** — `sessions/{id}/joinRequests/{userId}` (chosen) | Host queries pending requests with a simple `where('status', isEqualTo, 'pending')` inside one session. Firestore security rules can gate on `sessions/{id}` being the parent. Natural co-location with the session. | User's "my pending requests" requires a collectionGroup query on `joinRequests`. |
| **Top-level collection** — `joinRequests/{sessionId}_{userId}` | Deterministic IDs (ADR 0003 pattern). Cheap point reads for "did I already request to join session X?". | Host reads all pending requests with `where('sessionId', isEqualTo, x)` — requires a composite index; no simpler than subcollection. |

### JoinRequest doc ID

Use **deterministic ID `{userId}`** within the subcollection
`sessions/{sessionId}/joinRequests/{userId}`. This means the path
`sessions/{sessionId}/joinRequests/{userId}` is a point read — cheaply
tells us "did this user request to join?" and prevents duplicate requests.

### JoinRequest lifecycle after approval/decline

| Option | Pros | Cons |
|---|---|---|
| **Delete the doc** on approval or decline (chosen) | Doc existence = pending. No accumulation. Same logic as ADR 0004 for friend requests. | No history of past approvals or declines. |
| **Update status field** to `approved`/`declined` | History trail of who approved whom and when. Could power an audit log. | "Pending requests" query must filter by status. Docs accumulate forever. |

Mirrors ADR 0004 reasoning exactly — no consumer for the history at
current scope.

### Password hashing location

| Option | Pros | Cons |
|---|---|---|
| **Client-side (Flutter, `crypto` package)** (chosen) | No server infra needed. `crypto` is already mandated by CLAUDE.md. Salt generated on the client with `dart:math` secure random bytes. | Hash computed with client clock/entropy. A determined attacker with the hash and salt could brute-force offline. Acceptable for a study-session app; not a banking app. |
| **Cloud Function** | Hash never touches client. Harder to brute-force offline. | Requires Cloud Functions deployment. Out of scope for college project. Adds latency to session creation. |

## Decision

JoinRequest docs live as a **subcollection** at
`sessions/{sessionId}/joinRequests/{userId}` with deterministic doc ID
`{userId}`. Docs are **deleted** on approval or decline (not status-mutated).

Private session passwords are **hashed client-side** using SHA-256 with a
per-session salt stored alongside the hash in the format
`"<sha256hex>:<base64salt>"` in the `Session.passwordHash` field.

### Approval batch (public sessions)

When the host approves a join request, `participation_service.approveRequest`
executes a single WriteBatch:

1. **Delete** `sessions/{sessionId}/joinRequests/{userId}`.
2. **Create** `sessions/{sessionId}/members/{userId}` with card-render
   fields (see ADR 0008).
3. **Increment** `sessions/{sessionId}.participantCount` by 1.
4. **Increment** `users/{userId}.sessionsCount` by 1.

When the host declines: delete only the JoinRequest doc.

### Decline and leaving

- Decline: WriteBatch deletes the JoinRequest doc only.
- Leave (member leaves voluntarily): WriteBatch deletes the member doc,
  decrements `participantCount` on session, decrements `sessionsCount` on
  user.

### Private session join flow

1. User provides a plain-text password in the UI.
2. `participation_service.joinWithPassword` reads the session doc to get
   `passwordHash` (`"<sha256hex>:<base64salt>"`).
3. Service splits the string on `":"`, extracts salt (base64-decoded to bytes).
4. Service computes SHA-256 over `(salt bytes + password UTF-8 bytes)`.
5. If the hex digest matches the stored hex, proceed to step 6.
   Otherwise throw `DataException('Incorrect password')`.
6. WriteBatch: create member doc + increment counts (same batch as above).
   No JoinRequest doc is created for private sessions — password is the gate.

### Hash generation (session creation)

When a host creates a private session:

1. Generate 16 cryptographically random bytes using `dart:math`
   `Random.secure()`.
2. Compute SHA-256 over `(salt bytes + plaintext password UTF-8 bytes)`.
3. Store `"<sha256hex>:<base64(salt)>"` in `Session.passwordHash`.
4. Never log or return the plaintext password anywhere.

## Why we chose these options

Subcollection placement keeps join-request data co-located with the session.
The host's "review pending requests" UI needs one collection query inside
the session — simpler and more rule-enforceable than a top-level query.
The deterministic `{userId}` doc ID prevents duplicate requests without
a separate existence check.

Delete-on-resolve mirrors ADR 0004 exactly. We have no ratings or history
screen that needs to know "who was approved on what date"; we don't build
for consumers that don't exist.

Client-side hashing avoids Cloud Functions infrastructure and matches
the `crypto` package mandate from CLAUDE.md. The threat model for a
university study-session app does not require server-side hashing.

## Reversal cost

**Low for subcollection vs. top-level** — a one-time migration script
moves docs; service query changes are isolated to `participation_service`.

**Low for delete-on-resolve** — same reasoning as ADR 0004: switch from
delete to status-update requires one line of code; historical data simply
starts from the changeover date.

**Medium for hashing location** — moving to a Cloud Function requires
deploying infra, changing the service call from direct hash to an HTTPS
call or callable function, and re-hashing existing password fields.

## Constraints locked in by this decision

- JoinRequest doc path: `sessions/{sessionId}/joinRequests/{userId}`.
  Doc ID is always `{userId}` — prevents duplicate requests automatically.
- JoinRequest docs only ever exist in `pending` state in Firestore.
  `isApproved`/`isDeclined` getters on the model remain unused in writes.
- Private session `passwordHash` format: `"<sha256hex>:<base64salt>"`.
  Service code must parse this format; never store the two parts in
  separate fields (keeps the field atomic and easy to null-check).
- No JoinRequest doc is created for private session joins — password
  is the authorization mechanism, not a request-approval flow.
- `sessionsCount` on user doc is incremented on approved join or on
  session creation (host). Decremented on leave or cancel.
- The `joinRequests` constant in `FirestoreCollections` refers to the
  subcollection name `"joinRequests"` — it is used as
  `.collection('joinRequests')` on a session doc reference.

## See also

- ADR 0003 — deterministic ID pattern (reused here for JoinRequest doc IDs).
- ADR 0004 — delete-on-resolve pattern (reused here for JoinRequest lifecycle).
- ADR 0006 — session visibility defines when approval vs. password gate applies.
- ADR 0008 — member doc shape (fields written in the approval batch).
- ADR 0010 — fan-out rules when session is cancelled (affects pending JoinRequests).
- `lib/models/join_request.dart` — model (see ADR 0010 work order for changes).
- `lib/core/constants/firestore_collections.dart` — `joinRequests` constant.
