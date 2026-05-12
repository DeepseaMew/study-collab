# 0013 — Session group chat data model

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

Every session needs a group chat accessible to its confirmed members.
Three questions must be settled before implementation:

1. Where do group-chat messages live?
2. When is the chat "created," and how?
3. When a session is cancelled or deleted, what happens to the messages?

## Options considered

### Message path

| Option | Pros | Cons |
|---|---|---|
| **`sessions/{sessionId}/messages/{autoId}`** (chosen) | Already stubbed in `firestore.rules`. The `isSessionMember` helper already exists and gates access. No new collection needed. Co-located with session data — easier to delete atomically. | Subcollection message counts count against session doc size limits if stored on the parent (not an issue — we never store counts on the session doc itself). |
| **`groupChats/{sessionId}/messages/{autoId}`** (separate top-level) | Mirrors DM structure. Keeps chat data separate from session data. | Adds a third top-level collection that requires its own security rule block. The `isSessionMember` check would still need to do a cross-collection `get()`. No benefit over subcollection. |

### Creation trigger

| Option | Pros | Cons |
|---|---|---|
| **Implicit — no "chat doc" needed; messages collection is created by first message** | Fewest writes. | No place to store group-level metadata (last message preview, unread counters). Per-session unread counters need a home doc. |
| **Explicit — write a `sessions/{sessionId}/groupChat` doc in the same batch as session creation** (chosen) | Guarantees unread-counter fields exist on a stable doc. Consistent with the pattern of initializing state atomically at creation. No race condition when the first user opens chat before any messages exist. | One extra write per session creation — minimal cost. |

### Deletion behaviour

| Option | Pros | Cons |
|---|---|---|
| **Delete messages on `deleteSession`; leave messages on `cancelSession`** (chosen) | Cancelled sessions persist as history (matching ADR 0010 — member docs also survive cancel). Members can still read the chat history even after cancellation. Hard delete only happens when the session itself is permanently removed. | `deleteSession` must also fetch and delete all message docs — adds to the chunked batch in `session_service`. At college scale (few hundred messages), this is acceptable. |
| **Delete messages on both cancel and delete** | Clean slate either way. | Contradicts ADR 0010 philosophy (member docs survive cancel as history). Inconsistent. |

## Decision

Group-chat messages live at `sessions/{sessionId}/messages/{autoId}`.
A `sessions/{sessionId}/groupChat` metadata doc (holding per-member
unread counters and last-message preview) is written in the **same
`WriteBatch` as `createSession`**. Messages are deleted in
`deleteSession`'s chunked batch; they survive `cancelSession`.

### `sessions/{sessionId}/groupChat` doc schema

```
lastMessageText:     String?     // preview, max 100 chars
lastMessageAt:       Timestamp?
lastMessageSenderId: String?
unreadCounts:        Map<String, int>  // { uid: count } — see ADR 0014
createdAt:           Timestamp
```

### Message doc — `sessions/{sessionId}/messages/{autoId}`

```
senderId:  String      // matches request.auth.uid
text:      String      // plain text, max 2 000 chars
sentAt:    Timestamp   // server timestamp
```

(Same schema as DM messages — ADR 0012 — for consistency.)

## Why we chose these options

The `sessions/{sessionId}/messages/` path leverages the existing
`isSessionMember` rule and the existing `messages` stub in
`firestore.rules` — zero new rule infrastructure for message read/write
gates. Creating the `groupChat` metadata doc at session creation (rather
than lazily) avoids a race condition where the first user to open chat
finds no counter doc and must create it, causing a potential double-create.
Keeping messages alive on cancel is consistent with ADR 0010's philosophy
that cancel is a status change, not a destructive operation.

## Reversal cost

**Low for message path** — moving messages to a new top-level collection
would require a data migration and a new security rule block, but is
isolated to `chat_service` and `firestore.rules`.

**Low for deletion policy** — changing cancel to also delete messages is
a single service-code addition.

## Constraints locked in by this decision

- `session_service.createSession` MUST include a `batch.set` for
  `sessions/{sessionId}/groupChat` in the same `WriteBatch`. See
  "See also" for handoff note.
- `session_service.deleteSession` MUST fetch and delete all message docs
  in `sessions/{sessionId}/messages/` as part of its chunked batch
  (add to existing `_commitInChunks` ops).
- `session_service.cancelSession` MUST NOT delete message docs.
- The `groupChat` doc is the canonical home for per-session unread
  counters (see ADR 0014). Its path is
  `sessions/{sessionId}/groupChat` — a single known doc ID.
- Message schema is identical to DM messages (ADR 0012): `senderId`,
  `text`, `sentAt`. No extra fields needed for group context because
  the session ID is in the path.

## See also

- ADR 0008 — `createSession` batch structure (this ADR adds one op to it).
- ADR 0010 — cancel/delete semantics for session-related data.
- ADR 0012 — DM message schema (shared schema for consistency).
- ADR 0014 — unread counter design (defines `unreadCounts` map on the
  `groupChat` doc).
- ADR 0016 — security rules for session messages.
- `firestore.rules` — existing `sessions/{sessionId}/messages/{messageId}`
  stub at lines 116–125.
- `lib/services/session_service.dart` — `createSession` and `deleteSession`
  methods require amendment (handoff to firebase-specialist).
