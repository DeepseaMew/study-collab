# 0014 — Unread message counter design

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

The Messages tab and the session Chat button must show an unread count.
The counter must be incremented atomically with the message write (so a
message is never sent without bumping the unread count for its recipients)
and must be resettable to zero when the user opens the conversation.
No Cloud Functions are available, so everything must be client-driven.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Counter fields on the conversation doc** (chosen) | Single doc read gives both the conversation metadata (last message, participants) and the unread counts. The `FieldValue.increment` and reset can be batched with message write and conversation-open action respectively. | For group chat, a map `{ uid: count }` on the `groupChat` doc means every new message touches the doc once per conversation — not once per member. One write regardless of group size. |
| **B. Separate per-user-per-conversation doc (`chats/{dmId}/unread/{uid}`)** | Avoids hot-spot concerns on a single conversation doc. | Two Firestore reads to render the conversation list (conversation doc + unread doc). More doc path surface area. Hot-spot concern is irrelevant at college scale (<50 messages per session). |
| **C. Counter on the user doc (`users/{uid}.totalUnread`)** | One place to badge the app tab. | Cannot distinguish which conversation has unread messages. Does not tell the UI which conversation to highlight. |

## Decision

Store unread counters **on the conversation doc**, not in a separate
collection. Use two different field shapes for the two chat surfaces:

### DM conversations — `chats/{dmId}`

Two dedicated top-level fields (one per participant):

```
unreadCount_{uidA}: int   // 0 when uidA has read up to the latest message
unreadCount_{uidB}: int
```

The field name is computed as `'unreadCount_$uid'`. This is a Firestore
field name, not a nested map, to allow a direct `FieldValue.increment`
without rewriting the whole map.

### Session group chat — `sessions/{sessionId}/groupChat`

A single map field (supports variable-size groups):

```
unreadCounts: { uid1: int, uid2: int, ... }
```

Because Firestore does not support `FieldValue.increment` inside a map
field by path (`unreadCounts.uid`), the increment is written as:

```
'unreadCounts.$uid': FieldValue.increment(1)
```

(dot-notation field path, which Firestore supports in update calls.)

Reset to zero uses the same dot-notation update: `'unreadCounts.$uid': 0`.

### Write order — message send

A single `WriteBatch` per message send:

1. `batch.add` the message doc (`messages/{autoId}`).
2. `batch.update` the conversation doc:
   - `lastMessageText` (truncated to 100 chars)
   - `lastMessageAt = FieldValue.serverTimestamp()`
   - `lastMessageSenderId = senderId`
   - Increment each recipient's counter by 1
     (DM: one field; group: all members except sender via dot-notation).

For group chat, incrementing N-1 counters in one `update` call is a
single Firestore write (one document mutation, multiple field paths) — not
N writes. This keeps the cost at 2 writes per message (message doc +
conversation doc), regardless of group size.

### Write order — mark as read

When a user opens a conversation, `chat_service.markConversationRead` does
a single `update` to the conversation doc that sets the user's counter to 0.
This is NOT batched with anything else; it is a standalone write.

### Writes per message sent (budget)

| Surface | Writes |
|---|---|
| DM message send | 2 (message doc + conversation doc) |
| Group chat message send | 2 (message doc + groupChat doc) |
| Mark DM read | 1 |
| Mark group chat read | 1 |

## Why we chose option A

The conversation list screen must show each conversation with its unread
count. Option A returns both in a single document snapshot — no joins.
Option B doubles the reads for the conversation list. Option C cannot
power per-conversation highlighting. At college scale (a few dozen active
DMs and sessions), a map field on the `groupChat` doc will never be a
Firestore hot-spot (which requires sustained >1 write/sec to the same doc).

Storing DM counters as top-level fields (`unreadCount_uid`) rather than a
map allows direct `FieldValue.increment` on the field without rewriting the
whole map, which is a minor Firestore quirk but important for atomicity in
the batch.

## Reversal cost

**Low.** Counter fields can be moved to a separate subcollection doc
by adding a second doc and a second read in the conversation list query.
The batch write pattern in `chat_service` is the only call site that
changes.

## Constraints locked in by this decision

- The message send batch MUST include the counter increment. A message MUST
  NOT be written without the corresponding counter update in the same batch.
- Reset-to-zero MUST be called when a user enters a conversation screen,
  not when they receive a push notification (push is not wired yet).
- DM counter field name format: `'unreadCount_$uid'`. Service code must
  compute this string consistently; it appears in both the write path and
  the read/parse path of the `DmConversation` model.
- Group chat counter update uses Firestore dot-notation:
  `'unreadCounts.$uid': FieldValue.increment(1)`. Passing a plain map
  would overwrite all other counters.
- `lastMessageText` stored on the conversation doc is a preview only —
  truncated to 100 characters before writing. Full text is in the
  message subcollection.

## See also

- ADR 0012 — DM conversation doc schema (defines the fields amended here).
- ADR 0013 — session group chat `groupChat` doc schema.
- ADR 0008 — `FieldValue.increment` pattern already used for `friendsCount`
  and `participantCount`.
