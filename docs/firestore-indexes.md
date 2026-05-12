# Firestore Indexes

Required composite indexes for Study Collab queries.

When you add a query that needs an index, add it here AND create it in
Firebase Console (or `firestore.indexes.json` if using the Firebase CLI).

Firestore creates single-field indexes automatically. Composite indexes
(multiple fields, or `where` + `orderBy` on different fields) must be
declared explicitly.

---

## sessions

### Sessions hosted by a specific user (own profile session history)
- **Collection:** `sessions`
- **Fields:** `hostId` ASC, `startTime` DESC
- **Used by:** `session_service.watchHostedSessions(userId)` —
  pending implementation
- **Why:** filters by host then orders by date.

### Public sessions hosted by a specific user (other-user profile)
- **Collection:** `sessions`
- **Fields:** `hostId` ASC, `visibility` ASC, `startTime` DESC
- **Used by:** `session_service.watchHostedPublicSessions(userId)` —
  pending implementation
- **Why:** filters by host AND visibility, orders by date. Excludes
  private sessions from public profile views per ADR 0006.

### Public sessions in browse / discover feed
- **Collection:** `sessions`
- **Fields:** `visibility` ASC, `status` ASC, `startTime` ASC
- **Used by:** dashboard's discover feed — pending implementation
  (currently mock data)
- **Why:** filters by visibility (public only) and status (upcoming),
  orders chronologically.

### Public upcoming sessions filtered by subject
- **Collection:** `sessions`
- **Fields:** `visibility` ASC, `status` ASC, `subject` ASC, `startTime` ASC
- **Used by:** `session_service.browseBySubject(subject)` — subject filter
  in the discover feed
- **Why:** extends the base discover-feed query with a subject equality
  filter. Adding `subject` to the existing 3-field index requires a
  separate composite index. Added by ADR 0010.

---

## members (collection group)

### Sessions a user has joined
- **Collection group:** `members`
- **Fields:** `userId` ASC
- **Used by:** session_service queries that find sessions a user is
  in (independent of which session) — pending implementation
- **Note:** collection-group queries on a single field still need
  explicit enabling in Firebase Console.

### Sessions a user has joined, ordered by start time
- **Collection group:** `members`
- **Fields:** `userId` ASC, `sessionStartTime` DESC
- **Used by:** `session_service.watchJoinedSessions(userId)` — My Sessions
  screen ordered chronologically.
- **Why:** the unordered `userId`-only index cannot satisfy an `orderBy`
  on `sessionStartTime`. A second index with the ordering field is required.
  `sessionStartTime` is a denormalized field on the member doc (ADR 0008).
  Added by ADR 0010.

---

## joinRequests (subcollection and collection group)

### Pending join requests for a session (host approval list)
- **Collection:** `sessions/{sessionId}/joinRequests`
- **Fields:** `status` ASC, `requestedAt` ASC
- **Used by:** `participation_service.watchPendingRequests(sessionId)`
- **Why:** subcollection query filtering on `status == 'pending'` ordered
  by request time. Doc IDs are deterministic (`{userId}`) but the host
  needs an ordered list of all pending requests.
- **Note:** this is a subcollection index, not a collection-group index.
  Create it against the `joinRequests` collection ID.
  Added by ADR 0010.

### User's own pending join requests across all sessions
- **Collection group:** `joinRequests`
- **Fields:** `userId` ASC, `requestedAt` DESC
- **Used by:** `participation_service.watchMyPendingRequests(userId)` —
  "pending requests" badge count for the requesting user.
- **Why:** collection-group query by `userId` with recency ordering.
  Added by ADR 0010.

---

## friendRequests

No composite indexes needed.

All friend-request reads use point reads on deterministic doc IDs
(see ADR 0003). No `where` + `orderBy` queries.

The single-field `where('recipientId', isEqualTo: ...)` query in
`watchIncomingRequests` uses an auto-generated single-field index.

---

## friends (subcollection)

### Friends list ordered by recency
- **Collection:** `friends/{userId}/userFriends`
- **Fields:** `addedAt` DESC
- **Used by:** `friend_service.watchFriends(userId)`
- **Note:** single-field index, auto-generated.

---

## ratings

### Ratings received by a specific user, ordered by recency
- **Collection:** `ratings`
- **Query scope:** Collection
- **Fields:** `ratedUserId` ASC, `ratedAt` DESC
- **Used by:** future "list ratings for user X" queries (not yet wired in UI)
- **Why:** equality filter on `ratedUserId` combined with recency ordering
  requires a composite index. Point-reads by deterministic doc ID (used by
  `rating_service`) do NOT need this index.

---

## How to create indexes

### Option 1: Firebase Console
1. Go to Firebase Console → Firestore Database → Indexes tab.
2. Click "Add index", fill in collection ID and fields per the
   specs above.
3. Wait for the index to build (usually 1–5 minutes).

### Option 2: Firebase CLI
1. Edit `firestore.indexes.json` at repo root.
2. Run `firebase deploy --only firestore:indexes`.

### Convenient shortcut
If you run the app and a query fails because an index is missing,
the error message in the Flutter logs includes a direct **Firebase
Console URL** that creates the index for you with one click.
This is often the fastest way during development.
