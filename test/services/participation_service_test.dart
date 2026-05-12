// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/constants/firestore_collections.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Build a minimal Session object (used to pass to service methods that take
/// a Session rather than just a sessionId). The [id] MUST match the doc
/// seeded in Firestore so updates land on the right path.
Session _makeSession({
  required String id,
  required String hostId,
  String title = 'Test Session',
  Subject subject = Subject.computerScience,
  SessionVisibility visibility = SessionVisibility.public,
  String? passwordHash,
  int participantCount = 1,
}) {
  final now = DateTime(2026, 6, 1, 10);
  return Session(
    id: id,
    title: title,
    subject: subject,
    description: '',
    visibility: visibility,
    hostId: hostId,
    hostName: 'Host User',
    startTime: now,
    endTime: now.add(const Duration(hours: 2)),
    location: 'Room 101',
    capacity: 10,
    participantCount: participantCount,
    reviewsEnabled: true,
    createdAt: now,
    updatedAt: now,
    passwordHash: passwordHash,
    hashtags: const [],
  );
}

/// Seed a session document in Firestore.
Future<void> _seedSessionDoc(
  FakeFirebaseFirestore ffs,
  String sessionId, {
  String hostId = 'host-uid',
  String title = 'Test Session',
  int participantCount = 1,
  String? passwordHash,
  String visibility = 'public',
}) async {
  final now = Timestamp.fromDate(DateTime(2026, 6, 1, 10));
  await ffs.collection(FirestoreCollections.sessions).doc(sessionId).set({
    'title': title,
    'hostId': hostId,
    'subject': Subject.computerScience.name,
    'visibility': visibility,
    'status': SessionStatus.upcoming.name,
    'participantCount': participantCount,
    'capacity': 10,
    'startTime': now,
    'endTime': Timestamp.fromDate(DateTime(2026, 6, 1, 12)),
    'location': 'Room 101',
    'description': '',
    'reviewsEnabled': true,
    'createdAt': now,
    'updatedAt': now,
    'hashtags': [],
    'passwordHash': passwordHash,
  });
}

/// Seed a user document.
Future<void> _seedUser(
  FakeFirebaseFirestore ffs,
  String uid, {
  int sessionsCount = 0,
}) async {
  await ffs.collection(FirestoreCollections.users).doc(uid).set({
    'sessionsCount': sessionsCount,
    'username': uid,
  });
}

/// Read sessionsCount from user doc.
Future<int?> _sessionsCount(FakeFirebaseFirestore ffs, String uid) async {
  final snap = await ffs.collection(FirestoreCollections.users).doc(uid).get();
  return snap.data()?['sessionsCount'] as int?;
}

/// Read participantCount from session doc.
Future<int?> _participantCount(
  FakeFirebaseFirestore ffs,
  String sessionId,
) async {
  final snap = await ffs
      .collection(FirestoreCollections.sessions)
      .doc(sessionId)
      .get();
  return snap.data()?['participantCount'] as int?;
}

/// Generate a valid passwordHash for a given plain-text password,
/// using the same SHA-256+salt scheme as session_service / participation_service.
///
/// Format: `"<sha256hex>:<base64salt>"`
/// This is a test fixture helper — uses Random.secure() for a real salt,
/// matching the production algorithm so the hash round-trip test is meaningful.
String _hashPassword(String plainText) {
  final rng = Random.secure();
  final saltBytes = Uint8List.fromList(
    List<int>.generate(16, (_) => rng.nextInt(256)),
  );
  final passwordBytes = utf8.encode(plainText);
  final combined = Uint8List(saltBytes.length + passwordBytes.length)
    ..setRange(0, saltBytes.length, saltBytes)
    ..setRange(
      saltBytes.length,
      saltBytes.length + passwordBytes.length,
      passwordBytes,
    );
  final digest = sha256.convert(combined);
  return '${digest.toString()}:${base64.encode(saltBytes)}';
}

// ── requestJoin (public session) ──────────────────────────────────────────────

void main() {
  group('ParticipationService.requestJoin', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-1';
    const userId = 'user-abc';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);
      await _seedSessionDoc(ffs, sessionId);
    });

    test(
      'creates joinRequest doc under sessions/{id}/joinRequests/{userId}',
      () async {
        await service.requestJoin(
          sessionId: sessionId,
          userId: userId,
          username: 'Bob',
        );

        final snap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .doc(userId)
            .get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['userId'], equals(userId));
        expect(snap.data()!['username'], equals('Bob'));
      },
    );

    test('request status is pending', () async {
      await service.requestJoin(
        sessionId: sessionId,
        userId: userId,
        username: 'Bob',
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId)
          .get();

      expect(snap.data()!['status'], equals('pending'));
    });

    test('duplicate request by the same user throws DataException', () async {
      await service.requestJoin(
        sessionId: sessionId,
        userId: userId,
        username: 'Bob',
      );

      await expectLater(
        service.requestJoin(
          sessionId: sessionId,
          userId: userId,
          username: 'Bob',
        ),
        throwsA(isA<DataException>()),
      );
    });

    test('doc ID equals userId (deterministic, prevents duplicates)', () async {
      await service.requestJoin(
        sessionId: sessionId,
        userId: userId,
        username: 'Bob',
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId) // point read using userId as doc ID
          .get();

      expect(snap.exists, isTrue);
    });
  });

  // ── approveRequest ────────────────────────────────────────────────────────────

  group('ParticipationService.approveRequest', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-2';
    const hostId = 'host-uid';
    const requestUserId = 'requester-uid';

    Future<void> setupApproveScenario() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await _seedSessionDoc(
        ffs,
        sessionId,
        hostId: hostId,
        participantCount: 1,
      );
      await _seedUser(ffs, requestUserId, sessionsCount: 0);

      // Seed the pending join request.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(requestUserId)
          .set({
            'userId': requestUserId,
            'username': 'Requester',
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
          });
    }

    test('joinRequest doc is deleted after approval', () async {
      await setupApproveScenario();
      final session = _makeSession(id: sessionId, hostId: hostId);

      await service.approveRequest(
        session: session,
        callerUid: hostId,
        requestUserId: requestUserId,
        requestUsername: 'Requester',
      );

      final reqSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(requestUserId)
          .get();
      expect(
        reqSnap.exists,
        isFalse,
        reason: 'joinRequest doc must be deleted on approval (ADR 0009)',
      );
    });

    test('participant member doc is created with role=member', () async {
      await setupApproveScenario();
      final session = _makeSession(id: sessionId, hostId: hostId);

      await service.approveRequest(
        session: session,
        callerUid: hostId,
        requestUserId: requestUserId,
        requestUsername: 'Requester',
      );

      final memberSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(requestUserId)
          .get();

      expect(memberSnap.exists, isTrue);
      expect(memberSnap.data()!['role'], equals('member'));
      expect(memberSnap.data()!['userId'], equals(requestUserId));
    });

    test('participantCount incremented by 1', () async {
      await setupApproveScenario();
      final session = _makeSession(
        id: sessionId,
        hostId: hostId,
        participantCount: 1,
      );

      await service.approveRequest(
        session: session,
        callerUid: hostId,
        requestUserId: requestUserId,
        requestUsername: 'Requester',
      );

      expect(await _participantCount(ffs, sessionId), equals(2));
    });

    test("requestUser's sessionsCount incremented by 1", () async {
      await setupApproveScenario();
      final session = _makeSession(id: sessionId, hostId: hostId);

      await service.approveRequest(
        session: session,
        callerUid: hostId,
        requestUserId: requestUserId,
        requestUsername: 'Requester',
      );

      expect(await _sessionsCount(ffs, requestUserId), equals(1));
    });

    test(
      'all four Firestore state changes are present after approval (batch atomicity)',
      () async {
        await setupApproveScenario();
        final session = _makeSession(
          id: sessionId,
          hostId: hostId,
          participantCount: 1,
        );

        await service.approveRequest(
          session: session,
          callerUid: hostId,
          requestUserId: requestUserId,
          requestUsername: 'Requester',
        );

        // 1. Request doc deleted.
        final reqSnap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .doc(requestUserId)
            .get();
        expect(reqSnap.exists, isFalse, reason: 'op1: request doc deleted');

        // 2. Member doc created.
        final memberSnap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(requestUserId)
            .get();
        expect(memberSnap.exists, isTrue, reason: 'op2: member doc created');

        // 3. participantCount +1.
        expect(
          await _participantCount(ffs, sessionId),
          equals(2),
          reason: 'op3: participantCount incremented',
        );

        // 4. sessionsCount +1.
        expect(
          await _sessionsCount(ffs, requestUserId),
          equals(1),
          reason: 'op4: user sessionsCount incremented',
        );
      },
    );

    test('member doc contains all card-render fields (ADR 0008)', () async {
      await setupApproveScenario();
      final session = _makeSession(
        id: sessionId,
        hostId: hostId,
        title: 'Physics Study',
        subject: Subject.physics,
      );

      await service.approveRequest(
        session: session,
        callerUid: hostId,
        requestUserId: requestUserId,
        requestUsername: 'Requester',
      );

      final memberSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(requestUserId)
          .get();

      final mData = memberSnap.data()!;
      expect(mData['sessionTitle'], equals('Physics Study'));
      expect(mData['sessionSubject'], equals(Subject.physics.name));
      expect(mData['hostId'], equals(hostId));
      expect(mData['attended'], isFalse);
    });

    test('approving non-existent request should throw DataException', () async {
      await setupApproveScenario();
      final session = _makeSession(id: sessionId, hostId: hostId);

      await expectLater(
        service.approveRequest(
          session: session,
          callerUid: hostId,
          requestUserId: 'ghost-uid', // no joinRequest doc for this user
          requestUsername: 'Ghost',
        ),
        throwsA(isA<DataException>()),
      );
    });

    test(
      'only host can approve — non-host caller throws DataException',
      () async {
        await setupApproveScenario();
        final session = _makeSession(id: sessionId, hostId: hostId);

        await expectLater(
          service.approveRequest(
            session: session,
            callerUid: 'not-the-host',
            requestUserId: requestUserId,
            requestUsername: 'Requester',
          ),
          throwsA(isA<DataException>()),
        );
      },
    );
  });

  // ── rejectRequest ─────────────────────────────────────────────────────────────

  group('ParticipationService.declineRequest', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-3';
    const hostId = 'host-uid';
    const requestUserId = 'user-req';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await _seedSessionDoc(
        ffs,
        sessionId,
        hostId: hostId,
        participantCount: 1,
      );
      await _seedUser(ffs, requestUserId, sessionsCount: 0);

      // Seed joinRequest and member docs to verify they don't change.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(requestUserId)
          .set({'userId': requestUserId, 'status': 'pending'});
    });

    test('joinRequest doc is deleted after decline', () async {
      await service.declineRequest(
        sessionId: sessionId,
        callerUid: hostId,
        userId: requestUserId,
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(requestUserId)
          .get();
      expect(snap.exists, isFalse);
    });

    test('participantCount is unchanged after decline', () async {
      await service.declineRequest(
        sessionId: sessionId,
        callerUid: hostId,
        userId: requestUserId,
      );

      expect(
        await _participantCount(ffs, sessionId),
        equals(1),
        reason: 'decline must not increment participantCount',
      );
    });

    test("requestUser's sessionsCount is unchanged after decline", () async {
      await service.declineRequest(
        sessionId: sessionId,
        callerUid: hostId,
        userId: requestUserId,
      );

      expect(
        await _sessionsCount(ffs, requestUserId),
        equals(0),
        reason: 'decline must not increment or decrement user sessionsCount',
      );
    });

    test('no member doc is created after decline', () async {
      await service.declineRequest(
        sessionId: sessionId,
        callerUid: hostId,
        userId: requestUserId,
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(requestUserId)
          .get();
      expect(
        snap.exists,
        isFalse,
        reason: 'declined requester must not become a member',
      );
    });
  });

  // ── joinWithPassword (private session) ────────────────────────────────────────

  group('ParticipationService.joinWithPassword', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'private-session';
    const hostId = 'host-uid';
    const joinerUid = 'joiner-uid';
    const correctPassword = 'correctHorseBatteryStaple';

    late String storedHash;
    late Session sessionModel;

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      // Generate a hash for the correct password using the same algorithm.
      storedHash = _hashPassword(correctPassword);

      await _seedSessionDoc(
        ffs,
        sessionId,
        hostId: hostId,
        passwordHash: storedHash,
        visibility: 'private',
      );
      await _seedUser(ffs, joinerUid, sessionsCount: 0);

      sessionModel = _makeSession(
        id: sessionId,
        hostId: hostId,
        visibility: SessionVisibility.private,
        passwordHash: storedHash,
      );
    });

    test('correct password creates member doc and increments counts', () async {
      await service.joinWithPassword(
        session: sessionModel,
        userId: joinerUid,
        username: 'JoinerUser',
        plainTextPassword: correctPassword,
      );

      final memberSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(joinerUid)
          .get();
      expect(
        memberSnap.exists,
        isTrue,
        reason: 'correct password should create member doc',
      );
      expect(
        await _participantCount(ffs, sessionId),
        equals(2),
        reason: 'participantCount should increment on successful password join',
      );
      expect(
        await _sessionsCount(ffs, joinerUid),
        equals(1),
        reason:
            'user sessionsCount should increment on successful password join',
      );
    });

    test(
      'wrong password throws DataException and creates no member doc',
      () async {
        await expectLater(
          service.joinWithPassword(
            session: sessionModel,
            userId: joinerUid,
            username: 'JoinerUser',
            plainTextPassword: 'wrongPassword',
          ),
          throwsA(isA<DataException>()),
        );

        // Member doc must NOT have been created.
        final memberSnap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(joinerUid)
            .get();
        expect(
          memberSnap.exists,
          isFalse,
          reason: 'wrong password must not create a member doc',
        );
      },
    );

    test(
      'wrong password error is a DataException with a readable message',
      () async {
        try {
          await service.joinWithPassword(
            session: sessionModel,
            userId: joinerUid,
            username: 'JoinerUser',
            plainTextPassword: 'badPassword',
          );
          fail('Expected DataException was not thrown');
        } catch (e) {
          expect(e, isA<DataException>());
          // Must NOT be a raw Firestore error — service must translate it.
          final ex = e as DataException;
          expect(ex.message, isNotEmpty);
          // The message should mention password.
          expect(ex.message.toLowerCase(), contains('password'));
        }
      },
    );

    test(
      'hash round-trip: hashing the same plain password matches stored hash',
      () async {
        // This directly tests that _verifyPassword in the service correctly
        // parses and re-computes the hash. We call joinWithPassword with the
        // correct password and confirm it succeeds — which requires the hash
        // round-trip to work end-to-end.
        await service.joinWithPassword(
          session: sessionModel,
          userId: joinerUid,
          username: 'JoinerUser',
          plainTextPassword: correctPassword, // must match storedHash
        );

        final memberSnap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(joinerUid)
            .get();
        expect(
          memberSnap.exists,
          isTrue,
          reason: 'hash round-trip must succeed for correct password',
        );
      },
    );

    test('session with no passwordHash throws DataException', () async {
      final sessionWithNoHash = _makeSession(
        id: sessionId,
        hostId: hostId,
        visibility: SessionVisibility.private,
        // passwordHash not set
      );

      await expectLater(
        service.joinWithPassword(
          session: sessionWithNoHash,
          userId: joinerUid,
          username: 'JoinerUser',
          plainTextPassword: 'anyPassword',
        ),
        throwsA(isA<DataException>()),
      );
    });

    test('no joinRequest doc is created for private session join', () async {
      await service.joinWithPassword(
        session: sessionModel,
        userId: joinerUid,
        username: 'JoinerUser',
        plainTextPassword: correctPassword,
      );

      final reqSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(joinerUid)
          .get();
      expect(
        reqSnap.exists,
        isFalse,
        reason:
            'private session join via password must not create a joinRequest doc',
      );
    });
  });

  // ── leaveSession ──────────────────────────────────────────────────────────────

  group('ParticipationService.leaveSession', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-leave';
    const hostId = 'host-uid';
    const memberUid = 'member-uid';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await _seedSessionDoc(
        ffs,
        sessionId,
        hostId: hostId,
        participantCount: 2,
      );
      await _seedUser(ffs, memberUid, sessionsCount: 3);

      // Seed the member doc.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(memberUid)
          .set({
            'userId': memberUid,
            'role': 'member',
            'sessionStatus': SessionStatus.upcoming.name,
          });
    });

    test('member doc is deleted after leaving', () async {
      await service.leaveSession(sessionId: sessionId, userId: memberUid);

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(memberUid)
          .get();
      expect(snap.exists, isFalse);
    });

    test('participantCount decremented by 1', () async {
      await service.leaveSession(sessionId: sessionId, userId: memberUid);

      expect(await _participantCount(ffs, sessionId), equals(1));
    });

    test("user's sessionsCount decremented by 1", () async {
      await service.leaveSession(sessionId: sessionId, userId: memberUid);

      expect(await _sessionsCount(ffs, memberUid), equals(2));
    });

    test(
      'host cannot leave their own session — throws DataException',
      () async {
        // Seed the host's member doc with role=host.
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(hostId)
            .set({
              'userId': hostId,
              'role': 'host',
              'sessionStatus': SessionStatus.upcoming.name,
            });

        await expectLater(
          service.leaveSession(sessionId: sessionId, userId: hostId),
          throwsA(isA<DataException>()),
        );
      },
    );
  });

  // ── watchUserMemberships (collectionGroup) ────────────────────────────────────

  group('ParticipationService.watchUserMemberships', () {
    // NOTE: fake_cloud_firestore supports collectionGroup queries but does NOT
    // support ordering by a field that requires a composite index (userId ASC +
    // sessionStartTime DESC). The ordering clause is dropped silently or may
    // cause an error depending on version. We test doc filtering but not ordering.

    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const targetUid = 'target-user';
    const otherUid = 'other-user';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      // Seed two sessions.
      for (final sId in ['sess-A', 'sess-B', 'sess-C']) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sId)
            .collection(FirestoreCollections.members)
            .doc(targetUid)
            .set({
              'userId': targetUid,
              'role': 'member',
              'sessionTitle': 'Session $sId',
              'sessionStartTime': Timestamp.fromDate(DateTime(2026, 6, 1)),
              'sessionEndTime': Timestamp.fromDate(DateTime(2026, 6, 1, 2)),
              'sessionStatus': SessionStatus.upcoming.name,
              'sessionSubject': Subject.computerScience.name,
              'hostId': 'host-uid',
              'username': 'Target',
              'attended': false,
              'joinedAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
            });
      }

      // Seed a doc for a different user in one session — must NOT appear.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc('sess-A')
          .collection(FirestoreCollections.members)
          .doc(otherUid)
          .set({
            'userId': otherUid,
            'role': 'member',
            'sessionTitle': 'Session sess-A',
            'sessionStartTime': Timestamp.fromDate(DateTime(2026, 6, 1)),
            'sessionEndTime': Timestamp.fromDate(DateTime(2026, 6, 1, 2)),
            'sessionStatus': SessionStatus.upcoming.name,
            'sessionSubject': Subject.computerScience.name,
            'hostId': 'host-uid',
            'username': 'Other',
            'attended': false,
            'joinedAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
          });
    });

    test(
      'returns only docs where userId == callerUid across multiple sessions',
      () async {
        // collectionGroup with ordering may not work on all fake_cloud_firestore
        // versions. We call watchUserMemberships and test the first emission.
        final stream = service.watchUserMemberships(targetUid);
        final result = await stream.first;

        expect(
          result.length,
          equals(3),
          reason: 'should return exactly 3 membership docs for targetUid',
        );
        expect(
          result.every((p) => p.userId == targetUid),
          isTrue,
          reason: 'every returned participant must belong to targetUid',
        );
      },
      // Quarantine note: if fake_cloud_firestore does not support
      // collectionGroup + orderBy in the test environment, this test may fail
      // with a "requires index" or similar error. In that case, mark as skip
      // and test watchUserMemberships manually / with integration tests.
    );

    test('does not return other users membership docs', () async {
      final stream = service.watchUserMemberships(targetUid);
      final result = await stream.first;

      expect(
        result.any((p) => p.userId == otherUid),
        isFalse,
        reason: 'should not return docs for otherUid',
      );
    });
  });

  // ── declineRequest — security regression (Pass 2 H1 / M2) ───────────────────

  group('ParticipationService.declineRequest — security regression', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-sec';
    const hostId = 'host_123';
    const requestUserId = 'user_456';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await _seedSessionDoc(ffs, sessionId, hostId: hostId);

      // Seed a pending join request doc with doc ID == requestUserId.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(requestUserId)
          .set({'userId': requestUserId, 'status': 'pending'});
    });

    test(
      // Regression: declineRequest must enforce host-only authorization
      // (security-reviewer Pass 2 H1)
      'non-host caller throws DataException',
      () async {
        await expectLater(
          service.declineRequest(
            sessionId: sessionId,
            callerUid: 'someone_else_999',
            userId: requestUserId,
          ),
          throwsA(isA<DataException>()),
        );
      },
    );

    test(
      // Regression: declineRequest must enforce host-only authorization
      // (security-reviewer Pass 2 H1) — side-effect check
      'joinRequest doc is NOT deleted when non-host caller is rejected',
      () async {
        try {
          await service.declineRequest(
            sessionId: sessionId,
            callerUid: 'someone_else_999',
            userId: requestUserId,
          );
        } catch (_) {
          // Expected DataException — swallow it to check doc state.
        }

        final snap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .doc(requestUserId)
            .get();
        expect(
          snap.exists,
          isTrue,
          reason:
              'joinRequest doc must not be deleted when caller is unauthorized',
        );
      },
    );

    test(
      // Regression: declineRequest on non-existent session throws DataException
      // (security-reviewer Pass 2 H1)
      'non-existent session throws DataException',
      () async {
        await expectLater(
          service.declineRequest(
            sessionId: 'ghost_id',
            callerUid: 'anyone',
            userId: requestUserId,
          ),
          throwsA(isA<DataException>()),
        );
      },
    );
  });

  // ── watchPendingRequests — security regression (Pass 2 M2) ───────────────────

  group('ParticipationService.watchPendingRequests — security regression', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-wpr';
    const hostId = 'host_123';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      // Seed the session doc.
      await _seedSessionDoc(ffs, sessionId, hostId: hostId);

      final now = Timestamp.fromDate(DateTime(2026, 6, 1));

      // Seed 2 pending join request docs.
      for (final uid in ['requester-alpha', 'requester-beta']) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .doc(uid)
            .set({
              'userId': uid,
              'username': uid,
              'status': 'pending',
              'requestedAt': now,
            });
      }
    });

    test(
      // Regression: non-host caller must see empty list, not raw
      // permission-denied (security-reviewer Pass 2 M2)
      'non-host caller receives empty list',
      () async {
        final stream = service.watchPendingRequests(
          sessionId,
          callerUid: 'not_the_host',
        );
        await expectLater(stream.first, completion(isEmpty));
      },
    );

    test(
      // Regression: host caller must receive the actual pending requests
      // (security-reviewer Pass 2 M2)
      'host caller receives all pending requests',
      () async {
        final stream = service.watchPendingRequests(
          sessionId,
          callerUid: hostId,
        );
        final result = await stream.first;
        expect(
          result.length,
          equals(2),
          reason: 'host should see all 2 pending requests',
        );
      },
    );
  });

  // ── watchMyPendingRequests (collectionGroup) ───────────────────────────────────

  group('ParticipationService.watchMyPendingRequests', () {
    // NOTE: Same collectionGroup + orderBy caveat as watchUserMemberships.

    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const targetUid = 'target-user';
    const otherUid = 'other-user';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      final now = Timestamp.fromDate(DateTime(2026, 6, 1));

      // Target user has 2 pending requests across different sessions.
      for (final sId in ['sess-X', 'sess-Y']) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sId)
            .collection(FirestoreCollections.joinRequests)
            .doc(targetUid)
            .set({
              'userId': targetUid,
              'username': 'Target',
              'status': 'pending',
              'requestedAt': now,
            });
      }

      // Other user's pending request in the same sessions — must NOT appear.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc('sess-X')
          .collection(FirestoreCollections.joinRequests)
          .doc(otherUid)
          .set({
            'userId': otherUid,
            'username': 'Other',
            'status': 'pending',
            'requestedAt': now,
          });
    });

    test('returns only pending joinRequest docs for callerUid', () async {
      final stream = service.watchMyPendingRequests(targetUid);
      final result = await stream.first;

      expect(
        result.length,
        equals(2),
        reason: 'should return exactly 2 pending requests for targetUid',
      );
      expect(result.every((r) => r.userId == targetUid), isTrue);
    });

    test('does not return other users pending requests', () async {
      final stream = service.watchMyPendingRequests(targetUid);
      final result = await stream.first;

      expect(result.any((r) => r.userId == otherUid), isFalse);
    });
  });

  // ── cancelJoinRequest ─────────────────────────────────────────────────────────

  group('ParticipationService.cancelJoinRequest', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-cr';
    const userId = 'user-cr';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId)
          .set({'userId': userId, 'status': 'pending'});
    });

    test('pending joinRequest doc is deleted', () async {
      await service.cancelJoinRequest(sessionId: sessionId, userId: userId);

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc(userId)
          .get();
      expect(snap.exists, isFalse);
    });
  });

  // ── markAttended ─────────────────────────────────────────────────────────────

  group('ParticipationService.markAttended', () {
    late FakeFirebaseFirestore ffs;
    late ParticipationService service;

    const sessionId = 'session-att';
    const userId = 'attendee';

    setUp(() async {
      ffs = FakeFirebaseFirestore();
      service = ParticipationService(firestore: ffs);

      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(userId)
          .set({'userId': userId, 'role': 'member', 'attended': false});
    });

    test('attended field is set to true', () async {
      await service.markAttended(sessionId: sessionId, userId: userId);

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(userId)
          .get();
      expect(snap.data()!['attended'], isTrue);
    });
  });
}
