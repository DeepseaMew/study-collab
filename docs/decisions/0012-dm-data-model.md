# 0012 — Direct-message data model: conversation docs and message subcollection

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

The app needs 1-on-1 chat between friends. Before any service code is
written, the Firestore path, document schema, and ID strategy must be
fixed. The schema determines how security rules are written, how the
Messages tab queries for conversations, and how unread counts are stored.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Top-level `chats/{dmId}` + `chats/{dmId}/messages/` with deterministic `dmId`** (chosen) | Deterministic ID (`{smallerUid}_{largerUid}`) means "open a DM" is a single point read — no query needed. Matches the ADR 0003 pattern already in use for friend requests. Security rules check both participants by ID. | Two users can only have one DM thread (fine — we never need multiple). |
| **B. Top-level `chats/{dmId}` with random auto-ID** | No ordering constraint needed. | Opening a DM requires a query (`where('participants', arrayContains, uid) AND where('participants', arrayContains, otherUid)`) — two array-contains constraints which Firestore does not support in one query. Requires a workaround. |
| **C. `users/{uid}/chats/{otherUid}/messages/`** (per-user inbox) | Natural per-user query for the Messages tab (`users/{me}/chats`). | Messages must be duplicated under both users' paths. Writes doubled. Harder to enforce consistent state. |

## Decision

Store DM conversations at `chats/{dmId}` where `dmId` is the two
participant UIDs sorted alphabetically and joined with `_`
(e.g., `abc_xyz`). Messages live in `chats/{dmId}/messages/{autoId}`.

### Conversation doc — `chats/{dmId}`

```
participantIds:      [String]         // exactly two UIDs, sorted
lastMessageText:     String?          // preview (max 100 chars, truncated)
lastMessageAt:       Timestamp?       // for sorting the conversation list
lastMessageSenderId: String?          // to show "You: …" vs sender name
unreadCount_{uid}:   int (x2)        // per ADR 0014 (unread counter design)
createdAt:           Timestamp
```

`unreadCount_{uid}` fields are covered in ADR 0014.

### Message doc — `chats/{dmId}/messages/{autoId}`

```
senderId:  String      // matches request.auth.uid at write time
text:      String      // plain text, max 2 000 chars
sentAt:    Timestamp   // server timestamp
```

Auto-generated message IDs are sufficient — messages have no identity
outside their conversation, and we do not need point reads on individual
messages.

## Why we chose option A

Deterministic `dmId` (`{smallerUid}_{largerUid}`) makes "open or create a
DM" a single `set(merge: true)` with no existence check query, matching
exactly the pattern ADR 0003 proved works for friend requests. The
Messages tab query (`where('participantIds', arrayContains, myUid)`,
ordered by `lastMessageAt DESC`) works with a single array-contains
constraint. Option B's double-array-contains problem has no clean solution
in Firestore without a Cloud Function or a workaround that adds a composite
field — unnecessary complexity.

## Reversal cost

**Medium.** Changing the ID scheme would require migrating existing chat
docs to new IDs, updating `chat_service`, and patching security rules.
All downstream code that opens a DM by constructing the ID would also need
updating.

## Constraints locked in by this decision

- `dmId` is always `[uid1, uid2].sorted().join('_')`. Service code MUST
  compute this consistently — any deviation creates a second, orphan doc.
- `participantIds` array MUST contain exactly two UIDs. Security rules
  rely on `participantIds` for membership checks (ADR 0016).
- `lastMessageText` is a preview only — truncated to 100 chars in service
  code before writing. Full text lives only in the message subcollection.
- Message doc fields are immutable after creation (`update: if false` in
  rules). No editing or deletion in v1 (scope locked by human lead).
- `FirestoreCollections.chats` (`'chats'`) and
  `FirestoreCollections.messages` (`'messages'`) are already declared in
  `firestore_collections.dart` — no new constants needed.

## See also

- ADR 0003 — deterministic ID pattern (same principle reused here).
- ADR 0014 — unread counter design (defines `unreadCount_{uid}` fields).
- ADR 0015 — friendship enforcement for DMs.
- ADR 0016 — security rules for both chat surfaces.
- `lib/core/constants/firestore_collections.dart` — `chats`, `messages`
  constants already present.
- `firestore.rules` — `chats/{chatId}` stub currently set to `allow read,
  write: if false` — will be replaced by ADR 0016.
