import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/models/app_user.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/services/friend_service.dart';

// Firestore path constants (mirrors FirestoreCollections to avoid importing
// production constants here and risking accidental edits).
const _kUsers = 'users';
const _kFriends = 'friends';
const _kFriendRequests = 'friendRequests';
const _kUserFriends = 'userFriends';

// ── Fixtures ──────────────────────────────────────────────────────────────────

/// Minimal [AppUser] fixture for alice (id = 'alice').
AppUser _alice() => AppUser(
      id: 'alice',
      email: 'alice@kmutt.ac.th',
      username: 'Alice',
      bio: 'Alice bio',
      profilePhotoUrl: 'https://example.com/alice.jpg',
      academicLevel: AcademicLevel.undergraduate,
      studentYear: 2,
      faculty: 'Engineering',
      friendsCount: 0,
      sessionsCount: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Minimal [AppUser] fixture for bob (id = 'bob').
AppUser _bob() => AppUser(
      id: 'bob',
      email: 'bob@kmutt.ac.th',
      username: 'Bob',
      bio: 'Bob bio',
      profilePhotoUrl: 'https://example.com/bob.jpg',
      academicLevel: AcademicLevel.undergraduate,
      studentYear: 3,
      faculty: 'Science',
      friendsCount: 0,
      sessionsCount: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Seeds a user doc so batch.update(userRef, ...) in acceptRequest / unfriend
/// can succeed (fake_cloud_firestore requires the doc to exist for update).
Future<void> _seedUser(
  FakeFirebaseFirestore fakeFs,
  String uid, {
  int friendsCount = 0,
}) async {
  await fakeFs.collection(_kUsers).doc(uid).set({
    'username': uid == 'alice' ? 'Alice' : 'Bob',
    'profilePhotoUrl': 'https://example.com/$uid.jpg',
    'friendsCount': friendsCount,
    'sessionsCount': 0,
  });
}

/// Seeds both sides of a pre-existing friendship plus matching user docs.
Future<void> _seedFriendship(
  FakeFirebaseFirestore fakeFs, {
  int friendsCount = 5,
}) async {
  await _seedUser(fakeFs, 'alice', friendsCount: friendsCount);
  await _seedUser(fakeFs, 'bob', friendsCount: friendsCount);

  final now = Timestamp.now();

  // alice's view of bob
  await fakeFs
      .collection(_kFriends)
      .doc('alice')
      .collection(_kUserFriends)
      .doc('bob')
      .set({
    'username': 'Bob',
    'profilePhotoUrl': 'https://example.com/bob.jpg',
    'bio': 'Bob bio',
    'addedAt': now,
  });

  // bob's view of alice
  await fakeFs
      .collection(_kFriends)
      .doc('bob')
      .collection(_kUserFriends)
      .doc('alice')
      .set({
    'username': 'Alice',
    'profilePhotoUrl': 'https://example.com/alice.jpg',
    'bio': 'Alice bio',
    'addedAt': now,
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FriendService', () {
    // ── Test 1: sendRequest happy path ─────────────────────────────────────────

    test(
        'sendRequest writes a doc at friend_requests/{senderId}_{recipientId} '
        'with correct fields', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);
      final alice = _alice();
      final bob = _bob();

      // Act
      await service.sendRequest(fromUser: alice, toUser: bob);

      // Assert
      final docId = 'alice_bob';
      final snap =
          await fakeFs.collection(_kFriendRequests).doc(docId).get();

      expect(snap.exists, isTrue,
          reason: 'friend_requests/alice_bob must exist after sendRequest');

      final data = snap.data()!;
      expect(data['senderId'], equals('alice'));
      expect(data['recipientId'], equals('bob'));
      expect(data['senderUsername'], equals('Alice'));
      expect(data['senderPhotoUrl'], equals('https://example.com/alice.jpg'));
      expect(data['status'], equals('pending'));
      expect(data.containsKey('sentAt'), isTrue,
          reason: 'sentAt must be present (FieldValue.serverTimestamp())');
    });

    // ── Test 2: sendRequest self-request ───────────────────────────────────────

    test(
        'sendRequest throws DataException when sender and recipient are the same user',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);
      final alice = _alice();

      // Act + Assert
      await expectLater(
        service.sendRequest(fromUser: alice, toUser: alice),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Cannot send a friend request to yourself',
          ),
        ),
      );

      // Confirm no doc was written
      final snap =
          await fakeFs.collection(_kFriendRequests).doc('alice_alice').get();
      expect(snap.exists, isFalse,
          reason: 'no request doc should exist after a self-request rejection');
    });

    // ── Test 3: acceptRequest atomic batch ─────────────────────────────────────

    test(
        'acceptRequest deletes the request doc, creates both friend docs with '
        'denormalized fields, and increments both users friendsCount', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);
      final alice = _alice(); // currentUser (the one accepting)
      final bob = _bob();     // fromUser (the one who sent the request)

      // Seed user docs so batch.update succeeds
      await _seedUser(fakeFs, 'alice', friendsCount: 0);
      await _seedUser(fakeFs, 'bob', friendsCount: 0);

      // Seed the pending request doc (bob sent to alice → doc id = 'bob_alice')
      await fakeFs.collection(_kFriendRequests).doc('bob_alice').set({
        'senderId': 'bob',
        'recipientId': 'alice',
        'senderUsername': 'Bob',
        'senderPhotoUrl': 'https://example.com/bob.jpg',
        'status': 'pending',
        'sentAt': Timestamp.now(),
      });

      // Act
      await service.acceptRequest(currentUser: alice, fromUser: bob);

      // Assert 1 — request doc is deleted
      final requestSnap =
          await fakeFs.collection(_kFriendRequests).doc('bob_alice').get();
      expect(requestSnap.exists, isFalse,
          reason: 'pending request doc must be deleted after acceptRequest');

      // Assert 2 — alice's view of bob (friends/alice/userFriends/bob)
      final aliceViewOfBob = (await fakeFs
              .collection(_kFriends)
              .doc('alice')
              .collection(_kUserFriends)
              .doc('bob')
              .get())
          .data();
      expect(aliceViewOfBob, isNotNull,
          reason: 'friends/alice/userFriends/bob must exist');
      expect(aliceViewOfBob!['username'], equals('Bob'));
      expect(aliceViewOfBob['profilePhotoUrl'],
          equals('https://example.com/bob.jpg'));
      expect(aliceViewOfBob['bio'], equals('Bob bio'));
      expect(aliceViewOfBob.containsKey('addedAt'), isTrue,
          reason: 'addedAt must be present on the friend doc');

      // Assert 3 — bob's view of alice (friends/bob/userFriends/alice)
      final bobViewOfAlice = (await fakeFs
              .collection(_kFriends)
              .doc('bob')
              .collection(_kUserFriends)
              .doc('alice')
              .get())
          .data();
      expect(bobViewOfAlice, isNotNull,
          reason: 'friends/bob/userFriends/alice must exist');
      expect(bobViewOfAlice!['username'], equals('Alice'));
      expect(bobViewOfAlice['profilePhotoUrl'],
          equals('https://example.com/alice.jpg'));
      expect(bobViewOfAlice['bio'], equals('Alice bio'));
      expect(bobViewOfAlice.containsKey('addedAt'), isTrue,
          reason: 'addedAt must be present on the mirror friend doc');

      // Assert 4 — both users' friendsCount incremented from 0 to 1
      final aliceDoc =
          await fakeFs.collection(_kUsers).doc('alice').get();
      expect(aliceDoc.data()!['friendsCount'], equals(1),
          reason: 'alice friendsCount must be incremented to 1');

      final bobDoc = await fakeFs.collection(_kUsers).doc('bob').get();
      expect(bobDoc.data()!['friendsCount'], equals(1),
          reason: 'bob friendsCount must be incremented to 1');
    });

    // ── Test 4: declineRequest ─────────────────────────────────────────────────

    test(
        'declineRequest deletes the request doc and does not create friend docs '
        'or modify friendsCount on either user', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);

      // Seed user docs so we can verify friendsCount remains unchanged
      await _seedUser(fakeFs, 'alice', friendsCount: 2);
      await _seedUser(fakeFs, 'bob', friendsCount: 3);

      // Seed the pending request (bob sent to alice → 'bob_alice')
      await fakeFs.collection(_kFriendRequests).doc('bob_alice').set({
        'senderId': 'bob',
        'recipientId': 'alice',
        'senderUsername': 'Bob',
        'senderPhotoUrl': 'https://example.com/bob.jpg',
        'status': 'pending',
        'sentAt': Timestamp.now(),
      });

      // Act
      await service.declineRequest(
        fromUserId: 'bob',
        currentUserId: 'alice',
      );

      // Assert 1 — request doc is deleted
      final requestSnap =
          await fakeFs.collection(_kFriendRequests).doc('bob_alice').get();
      expect(requestSnap.exists, isFalse,
          reason: 'request doc must be deleted after declineRequest');

      // Assert 2 — no friend doc created for alice
      final aliceViewOfBob = await fakeFs
          .collection(_kFriends)
          .doc('alice')
          .collection(_kUserFriends)
          .doc('bob')
          .get();
      expect(aliceViewOfBob.exists, isFalse,
          reason: 'declineRequest must not create a friend doc for alice');

      // Assert 3 — no friend doc created for bob
      final bobViewOfAlice = await fakeFs
          .collection(_kFriends)
          .doc('bob')
          .collection(_kUserFriends)
          .doc('alice')
          .get();
      expect(bobViewOfAlice.exists, isFalse,
          reason: 'declineRequest must not create a friend doc for bob');

      // Assert 4 — friendsCount unchanged on both users
      final aliceDoc =
          await fakeFs.collection(_kUsers).doc('alice').get();
      expect(aliceDoc.data()!['friendsCount'], equals(2),
          reason: 'alice friendsCount must not change after declineRequest');

      final bobDoc = await fakeFs.collection(_kUsers).doc('bob').get();
      expect(bobDoc.data()!['friendsCount'], equals(3),
          reason: 'bob friendsCount must not change after declineRequest');
    });

    // ── Test 5: unfriend atomic batch ──────────────────────────────────────────

    test(
        'unfriend deletes both friend docs atomically and decrements both '
        'users friendsCount from 5 to 4', () async {
      // Arrange — pre-seed a full friendship
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);

      await _seedFriendship(fakeFs, friendsCount: 5);

      // Verify pre-conditions
      expect(
        (await fakeFs
                .collection(_kFriends)
                .doc('alice')
                .collection(_kUserFriends)
                .doc('bob')
                .get())
            .exists,
        isTrue,
        reason: 'friends/alice/userFriends/bob must exist before unfriend',
      );
      expect(
        (await fakeFs
                .collection(_kFriends)
                .doc('bob')
                .collection(_kUserFriends)
                .doc('alice')
                .get())
            .exists,
        isTrue,
        reason: 'friends/bob/userFriends/alice must exist before unfriend',
      );

      // Act
      await service.unfriend(
        currentUserId: 'alice',
        otherUserId: 'bob',
      );

      // Assert 1 — alice's friend doc for bob is deleted
      final aliceViewOfBob = await fakeFs
          .collection(_kFriends)
          .doc('alice')
          .collection(_kUserFriends)
          .doc('bob')
          .get();
      expect(aliceViewOfBob.exists, isFalse,
          reason: 'friends/alice/userFriends/bob must be deleted after unfriend');

      // Assert 2 — bob's friend doc for alice is deleted
      final bobViewOfAlice = await fakeFs
          .collection(_kFriends)
          .doc('bob')
          .collection(_kUserFriends)
          .doc('alice')
          .get();
      expect(bobViewOfAlice.exists, isFalse,
          reason: 'friends/bob/userFriends/alice must be deleted after unfriend');

      // Assert 3 — alice's friendsCount decremented from 5 to 4
      final aliceDoc =
          await fakeFs.collection(_kUsers).doc('alice').get();
      expect(aliceDoc.data()!['friendsCount'], equals(4),
          reason: 'alice friendsCount must be decremented from 5 to 4');

      // Assert 4 — bob's friendsCount decremented from 5 to 4
      final bobDoc = await fakeFs.collection(_kUsers).doc('bob').get();
      expect(bobDoc.data()!['friendsCount'], equals(4),
          reason: 'bob friendsCount must be decremented from 5 to 4');
    });

    // ── Test 6: watchFriendshipStatus — self ───────────────────────────────────

    test(
        'watchFriendshipStatus emits FriendshipStatus.self immediately when '
        'currentUserId == otherUserId', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = FriendService(firestore: fakeFs);

      // Act — use .first with a timeout to avoid hanging the test runner
      final status = await service
          .watchFriendshipStatus(
            currentUserId: 'alice',
            otherUserId: 'alice',
          )
          .first
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TestFailure('watchFriendshipStatus did not emit within 5s'),
          );

      // Assert
      expect(status, equals(FriendshipStatus.self),
          reason: 'looking at your own profile must emit FriendshipStatus.self');
    });
  });
}
