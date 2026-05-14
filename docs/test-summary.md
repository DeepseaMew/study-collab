# Backend Test Coverage — Sprint Summary

_Generated 2026-05-14. 26 unit tests across 3 services._

## Chat Service (`chat_service_test.dart`)

| # | Test description | Method | Status |
|---|------------------|--------|--------|
| 1 | dmId returns alphabetically sorted uid pair joined by underscore | `dmId` | ✅ |
| 2 | getOrCreateDm creates chats doc containing participantIds, lastMessageAt and createdAt | `getOrCreateDm` | ✅ |
| 3 | getOrCreateDm does NOT overwrite lastMessageAt on second call | `getOrCreateDm` | ✅ |
| 4 | getOrCreateDm throws DataException when users are not friends | `getOrCreateDm` | ✅ |
| 5 | sendDmMessage writes a message doc and increments unreadCount for recipient | `sendDmMessage` | ✅ |
| 6 | sendDmMessage throws DataException when friendship has been revoked | `sendDmMessage` | ✅ |
| 7 | markDmRead resets unreadCount for the specified user to 0 | `markDmRead` | ✅ |

## Session Service (`session_service_test.dart`)

| # | Test description | Method | Status |
|---|------------------|--------|--------|
| 1 | createSession writes session doc with correct fields and host member doc | `createSession` | ✅ |
| 2 | createSession for a private session hashes password — plaintext must not appear in Firestore | `createSession` | ✅ |
| 3 | createSession for a public session does not store passwordHash in Firestore | `createSession` | ✅ |
| 4 | editSession allows the host to update session fields | `editSession` | ✅ |
| 5 | editSession throws DataException when callerUid is not the host | `editSession` | ✅ |
| 6 | deleteSession removes session doc, member docs, joinRequest docs, groupChat messages, and meta | `deleteSession` | ✅ |
| 7 | watchPublicSessions returns only sessions with visibility == public and status == upcoming | `watchPublicSessions` | ✅ |
| 8 | createSession throws DataException when a private session has no password | `createSession` | ✅ |
| 9 | editSession throws DataException when session does not exist | `editSession` | ✅ |
| 10 | cancelSession marks session cancelled, decrements non-host sessionsCount, writes sessionCancelled notification, deletes joinRequests | `cancelSession` | ✅ |
| 11 | cancelSession does not throw when called with a wrong hostId — host identity enforced by Firestore rules only | `cancelSession` | ✅ |
| 12 | postponeSession updates session times, member docs, writes sessionPostponed notification, does NOT delete joinRequests or change sessionsCount | `postponeSession` | ✅ |
| 13 | postponeSession throws DataException when session does not exist | `postponeSession` | ✅ |

## Friend Service (`friend_service_test.dart`)

| # | Test description | Method | Status |
|---|------------------|--------|--------|
| 1 | sendRequest writes a doc at friend_requests/{senderId}_{recipientId} with correct fields | `sendRequest` | ✅ |
| 2 | sendRequest throws DataException when sender and recipient are the same user | `sendRequest` | ✅ |
| 3 | acceptRequest deletes request doc, creates both friend docs with denormalized fields, increments both users friendsCount | `acceptRequest` | ✅ |
| 4 | declineRequest deletes request doc, does not create friend docs or modify friendsCount | `declineRequest` | ✅ |
| 5 | unfriend deletes both friend docs atomically and decrements both users friendsCount from 5 to 4 | `unfriend` | ✅ |
| 6 | watchFriendshipStatus emits FriendshipStatus.self when currentUserId == otherUserId | `watchFriendshipStatus` | ✅ |

## Totals

| Service | Tests | Status |
|---------|-------|--------|
| Chat Service | 7 | All passing |
| Session Service | 13 | All passing |
| Friend Service | 6 | All passing |
| **Total** | **26** | **All passing** |
