# 0017 — Chat service interface

**Date:** 2026-05-12
**Status:** Proposed
**Decided by:** Architect agent + human lead

## Problem

Before `chat_service.dart` is implemented, the service interface must be
defined so that flutter-engineer can wire providers and screens without
waiting for the implementation, and so that firebase-specialist has a
clear contract to fill. The interface must cover both chat surfaces
(DM and session group chat) and match the existing service pattern
(`watchX` → `StreamProvider`, `mutationX` → `Future<void>`).

## Options considered

Two real options exist for structuring the service:

| Option | Pros | Cons |
|---|---|---|
| **Single `ChatService` with methods for both DM and session chat** (chosen) | One service file, one provider. DM and session chat share the same message schema (ADR 0012/0013) and the same send-and-update-counter batch logic — factoring into one service avoids duplication. | Slightly larger file. |
| **Two services: `DmService` and `SessionChatService`** | Smaller files, clearly separated. | Duplication of the send-message batch logic which is identical for both surfaces. Two service-wrapper providers to manage. |

## Decision

One `ChatService` class, one `chatServiceProvider` at the bottom of
`lib/services/chat_service.dart`. Methods are grouped by surface below.

### Models required (new files — handoff to firebase-specialist)

**`lib/models/dm_conversation.dart`**

```
class DmConversation {
  final String id;                  // dmId = '{smallerUid}_{largerUid}'
  final List<String> participantIds;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCountForMe;       // parsed by service from 'unreadCount_{myUid}' field
  final DateTime createdAt;
  // fromFirestore(doc, myUid), toFirestore(), copyWith()
}
```

**`lib/models/chat_message.dart`**

```
class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;
  // fromFirestore(doc), toFirestore(), copyWith()
}
```

**`lib/models/group_chat_meta.dart`**

```
class GroupChatMeta {
  final String sessionId;           // parent session ID
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final int unreadCountForMe;       // parsed from unreadCounts[myUid]
  // fromFirestore(doc, sessionId, myUid), toFirestore(), copyWith()
}
```

### Service interface (Dart pseudo-code — not implementation)

```dart
class ChatService {
  // ── DM surface ──────────────────────────────────────────────────────────────

  /// Returns the deterministic DM conversation doc ID for two users.
  String dmId(String uidA, String uidB);
  // Implementation: [uidA, uidB]..sort(), then join('_')

  /// Ensure a DM conversation doc exists (idempotent set with merge: true).
  /// Throws DataException if the two users are not friends.
  /// Called when user taps "Message" on a profile.
  Future<String> openOrCreateDm({
    required String currentUserId,
    required String otherUserId,
  });

  /// Watch the list of DM conversations for [userId], ordered by
  /// lastMessageAt DESC. Used by the Messages tab.
  ///
  /// Required Firestore index:
  ///   Collection: chats
  ///   Fields: participantIds (array-contains), lastMessageAt DESC
  Stream<List<DmConversation>> watchDmConversations({
    required String userId,
  });

  /// Watch messages in a DM conversation, ordered by sentAt ASC.
  Stream<List<ChatMessage>> watchDmMessages(String dmId);

  /// Send a text message in a DM.
  /// Batch: add message doc + update conversation doc (lastMessage + counter).
  /// Throws DataException if not friends with the other participant.
  Future<void> sendDmMessage({
    required String dmId,
    required String senderId,
    required String recipientId,
    required String text,
  });

  /// Reset the current user's unread count on a DM conversation to 0.
  /// Called when the user opens the conversation screen.
  Future<void> markDmRead({
    required String dmId,
    required String userId,
  });

  // ── Session group chat surface ───────────────────────────────────────────────

  /// Watch messages in a session group chat, ordered by sentAt ASC.
  Stream<List<ChatMessage>> watchGroupMessages(String sessionId);

  /// Watch the group chat metadata doc for a session (for unread count
  /// and last message preview on the session detail screen).
  Stream<GroupChatMeta?> watchGroupChatMeta({
    required String sessionId,
    required String currentUserId,
  });

  /// Send a text message in a session group chat.
  /// Batch: add message doc + update groupChat doc (lastMessage + counter map).
  /// Fetches current member list to build the counter increment map.
  Future<void> sendGroupMessage({
    required String sessionId,
    required String senderId,
    required String text,
    required List<String> memberIds,  // all confirmed member UIDs including sender
  });

  /// Reset the current user's unread count in a group chat to 0.
  Future<void> markGroupRead({
    required String sessionId,
    required String userId,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────
final chatServiceProvider = Provider<ChatService>((ref) => ChatService());
```

### Riverpod providers (hand-written, no codegen — ADR 0002)

To be declared in `lib/features/chat/providers/chat_providers.dart`:

```dart
// DM conversation list
final dmConversationsProvider = StreamProvider.family<List<DmConversation>, String>(
  (ref, userId) => ref.watch(chatServiceProvider).watchDmConversations(userId: userId),
);

// DM message stream
final dmMessagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, dmId) => ref.watch(chatServiceProvider).watchDmMessages(dmId),
);

// Group message stream
final groupMessagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, sessionId) => ref.watch(chatServiceProvider).watchGroupMessages(sessionId),
);

// Group chat metadata (unread count for session detail badge)
// Takes a record (sessionId, currentUserId) as a family param.
final groupChatMetaProvider =
  StreamProvider.family<GroupChatMeta?, (String, String)>(
    (ref, args) {
      final (sessionId, userId) = args;
      return ref.watch(chatServiceProvider).watchGroupChatMeta(
        sessionId: sessionId,
        currentUserId: userId,
      );
    },
  );
```

## Why we chose a single service

The send-message batch logic — write message doc, update conversation doc
with last-message preview, and increment recipient counters — is identical
for both surfaces. A shared private `_sendMessage` helper inside `ChatService`
avoids writing the same batch logic twice while keeping the two public APIs
distinct. One provider at the bottom of one file also matches the existing
service-wrapper pattern (`userServiceProvider`, `sessionServiceProvider`, etc.)
so there is no new pattern to explain.

## Reversal cost

**Low.** Splitting into two services later is a refactor: move methods into
two files, update the provider declarations in `chat_providers.dart`, and
update all `ref.watch(chatServiceProvider)` call sites. The data model does
not change.

## Constraints locked in by this decision

- `ChatService` lives in `lib/services/chat_service.dart`.
  `chatServiceProvider` is declared at the bottom of that file (matching
  ADR 0002 / CLAUDE.md service-wrapper pattern).
- `lib/features/chat/providers/chat_providers.dart` holds Riverpod providers.
  No providers inside `lib/services/`.
- `sendDmMessage` and `openOrCreateDm` MUST perform the friendship check
  (ADR 0015) before any Firestore write.
- `sendGroupMessage` takes `memberIds` as a parameter — the caller (provider
  or widget) is responsible for passing the current confirmed member list.
  The service does not query members itself to avoid double-reads when the
  caller already has the member list from `watchSessionMembers`.
- `markDmRead` and `markGroupRead` are fire-and-forget from the UI — they
  are called on screen open and do not need to complete before the screen
  renders.
- `DmConversation`, `ChatMessage`, and `GroupChatMeta` follow the standard
  model contract: `fromFirestore`, `toFirestore`, `copyWith`. No Freezed.

## See also

- ADR 0002 — hand-written Riverpod providers.
- ADR 0012 — DM conversation doc schema.
- ADR 0013 — session group chat schema.
- ADR 0014 — unread counter fields (drives field name computation in service).
- ADR 0015 — friendship enforcement (service must call `exists` check).
- ADR 0016 — security rules (service writes must satisfy the rule predicates).
- `lib/services/friend_service.dart` — friendship check path used in
  `openOrCreateDm` and `sendDmMessage`.
- `lib/services/session_service.dart` — `createSession` and `deleteSession`
  require amendment (see ADR 0013).
