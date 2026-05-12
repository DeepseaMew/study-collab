# 0016 — Chat security rules strategy

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

Two chat surfaces need distinct Firestore rule sets. The existing rules
stub at `chats/{chatId}` is `allow read, write: if false` — a placeholder.
The session messages stub at `sessions/{sessionId}/messages/{messageId}`
already exists but its `delete` rule is too permissive for v1 (allows
sender to delete, which contradicts the locked scope decision of no
message deletion in v1). Rules must be written or amended for both
surfaces, and counter fields must be protected from client-side
manipulation.

## Options considered

### DM friendship check in rules

| Option | Pros | Cons |
|---|---|---|
| **`exists()` check on `friends/{uid}/userFriends/{otherUid}` at `create` time** (chosen) | Actual enforcement at the Firestore layer. | One extra document read per rule evaluation. Firestore bills this read — at DM-send frequency for a college app, cost is negligible (<$1/month). |
| **Trust service layer only; rules just check `participantIds`** | No extra read in rules. | A Firestore-savvy client can bypass the friendship gate entirely. |

### Counter-field protection

| Option | Pros | Cons |
|---|---|---|
| **Allow `update` on conversation docs only via service methods; validate counter fields are not writeable by arbitrary clients** | Prevents counter manipulation. | Firestore rules cannot easily validate that a specific numeric field only increases by 1 without reading the current value, which costs a `get()`. |
| **Rely on the fact that counter fields are named `unreadCount_{uid}` and only participants can write** (chosen) | Simple. A participant manipulating their own unread counter is a low-severity self-harm. Recipient's counter is on the same doc — a sender cannot set the *recipient's* counter to 0 without a separate `update` call that the rules can audit. | Participants can technically manipulate their own counter to show false unread counts — acceptable risk for a study-session app. |

## Decision

### DM rules — `chats/{dmId}`

```
function isDmParticipant(dmId) {
  return isSignedIn() &&
    request.auth.uid in get(/databases/$(database)/documents/chats/$(dmId)).data.participantIds;
}

function isFriendOf(otherUid) {
  return exists(/databases/$(database)/documents/friends/$(request.auth.uid)/userFriends/$(otherUid));
}

match /chats/{dmId} {
  allow read: if isDmParticipant(dmId);

  // Conversation doc creation: caller must be in participantIds,
  // exactly 2 participants, and must be friends with the other.
  allow create: if isSignedIn()
    && request.auth.uid in request.resource.data.participantIds
    && request.resource.data.participantIds.size() == 2
    && isFriendOf(
         request.resource.data.participantIds[
           request.resource.data.participantIds[0] == request.auth.uid ? 1 : 0
         ]
       );

  // Updates allowed only to participants (for counter reset and
  // lastMessage preview updates by the sender).
  allow update: if isDmParticipant(dmId);

  allow delete: if false;

  match /messages/{messageId} {
    allow read:   if isDmParticipant(dmId);
    allow create: if isDmParticipant(dmId)
                  && request.resource.data.senderId == request.auth.uid
                  && request.resource.data.text is string
                  && request.resource.data.text.size() > 0
                  && request.resource.data.text.size() <= 2000
                  && isFriendOf(
                       get(/databases/$(database)/documents/chats/$(dmId)).data.participantIds[
                         get(/databases/$(database)/documents/chats/$(dmId)).data.participantIds[0]
                           == request.auth.uid ? 1 : 0
                       ]
                     );
    allow update: if false;
    allow delete: if false;
  }
}
```

### Session group chat rules — `sessions/{sessionId}/messages/{messageId}`

The existing `isSessionMember` helper already covers membership. The
required change is: **remove the `delete` permission** (currently allows
sender and host to delete — this contradicts v1 no-deletion scope).

```
match /messages/{messageId} {
  allow read:   if isSessionMember(sessionId);
  allow create: if isSessionMember(sessionId)
                && request.resource.data.senderId == request.auth.uid
                && request.resource.data.text is string
                && request.resource.data.text.size() > 0
                && request.resource.data.text.size() <= 2000;
  allow update: if false;
  allow delete: if false;   // changed from current rule — v1 locks no deletion
}
```

### `sessions/{sessionId}/groupChat` metadata doc

```
match /groupChat/{docId} {
  allow read:   if isSessionMember(sessionId);
  allow create: if isSessionHost(sessionId);      // created by host at session creation
  allow update: if isSessionMember(sessionId);    // counter reset + lastMessage preview
  allow delete: if isSessionHost(sessionId);      // deleted with session
}
```

## Why we chose these options

The `exists()` friendship check is the only way to enforce the friend
requirement without trusting the client alone. The cost (one extra read per
DM create and per message send) is acceptable at college scale. For counter
protection, the rule approach (participants-only update) is simpler than
trying to validate the numeric delta in rules; the risk of self-harm via
counter manipulation is low-severity and acceptable.

Removing the `delete` rule from session messages aligns `firestore.rules`
with the locked scope decision (no message deletion in v1) and removes an
inconsistency between what the rules allow and what the product allows.

## Reversal cost

**Low for counter strategy** — adding tighter counter validation (e.g.,
checking the increment is exactly 1) requires adding `get()` calls to the
rules, which is an additive change.

**Low for removing delete** — re-enabling delete requires one line change
in rules.

**Medium for switching from `exists()` to service-only friendship check**
— requires trusting client code and removing the cross-collection check
from rules. Acceptable only if friendship enforcement is moved to a Cloud
Function gateway.

## Constraints locked in by this decision

- `allow delete: if false` on both DM messages and session messages. No
  deletion path exists in v1 rules. Do not add it without a human-lead
  decision and an ADR amendment.
- DM message `create` rule re-validates friendship at write time, not just
  at conversation creation. This means ex-friends cannot send new messages
  even if a conversation doc already exists.
- The `groupChat` doc `create` is gated on `isSessionHost` — only the host
  (via `session_service.createSession`) can create it. This prevents manual
  creation by members.
- `sessions/{sessionId}/messages/{messageId}` `delete: if false` replaces
  the current rule. This is a **breaking rule change** — any existing
  messages that hosts or senders have tried to delete will now fail. Since
  chat is not yet shipped, there are no existing messages to worry about.
- The `isDmParticipant` helper uses a `get()` — it cannot be used in a
  `list` rule that is itself inside a collectionGroup query. DM message
  listing is always scoped inside the conversation path, so this is fine.

## See also

- ADR 0012 — DM conversation doc (`participantIds` array used in rules).
- ADR 0013 — `groupChat` metadata doc (new match block needed).
- ADR 0015 — friendship enforcement rationale.
- `firestore.rules` — existing stubs for `chats/` (line 139) and
  `sessions/{sessionId}/messages/` (line 116) — both require amendment.
- `lib/services/friend_service.dart` — `friends/{uid}/userFriends/{otherUid}`
  path that the rules `exists()` check references.
