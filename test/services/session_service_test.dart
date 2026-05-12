// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/constants/firestore_collections.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/session_service.dart';

// ── Test helpers ─────────────────────────────────────────────────────────────

/// Minimal session fixture. [id] is ignored by createSession (auto-generated),
/// but is required by the Session constructor.
Session _makeSession({
  String id = 'dummy-id',
  String hostId = 'host-uid',
  String hostName = 'Alice',
  String title = 'Test Session',
  Subject subject = Subject.computerScience,
  SessionVisibility visibility = SessionVisibility.public,
  String? passwordHash,
  int capacity = 10,
  int? studentYear,
  AcademicLevel? academicLevel,
}) {
  final now = DateTime(2026, 6, 1, 10);
  return Session(
    id: id,
    title: title,
    subject: subject,
    description: 'A test session',
    visibility: visibility,
    hostId: hostId,
    hostName: hostName,
    startTime: now,
    endTime: now.add(const Duration(hours: 2)),
    location: 'Room 101',
    capacity: capacity,
    reviewsEnabled: true,
    createdAt: now,
    updatedAt: now,
    passwordHash: passwordHash,
    studentYear: studentYear,
    academicLevel: academicLevel,
    hashtags: const ['flutter', 'study'],
  );
}

/// Seeds a user document so batch updates on the user doc succeed.
Future<void> _seedUser(
  FakeFirebaseFirestore ffs,
  String uid, {
  int sessionsCount = 0,
}) async {
  await ffs
      .collection(FirestoreCollections.users)
      .doc(uid)
      .set({'sessionsCount': sessionsCount, 'username': uid});
}

/// Helper: read session doc data.
Future<Map<String, dynamic>?> _sessionData(
  FakeFirebaseFirestore ffs,
  String sessionId,
) async {
  final snap = await ffs
      .collection(FirestoreCollections.sessions)
      .doc(sessionId)
      .get();
  return snap.data();
}

/// Helper: count docs in a sub-collection.
Future<int> _memberCount(FakeFirebaseFirestore ffs, String sessionId) async {
  final snap = await ffs
      .collection(FirestoreCollections.sessions)
      .doc(sessionId)
      .collection(FirestoreCollections.members)
      .get();
  return snap.docs.length;
}

/// Helper: read user sessionsCount.
Future<int?> _sessionsCount(FakeFirebaseFirestore ffs, String uid) async {
  final snap = await ffs
      .collection(FirestoreCollections.users)
      .doc(uid)
      .get();
  return snap.data()?['sessionsCount'] as int?;
}

// ── createSession ─────────────────────────────────────────────────────────────

void main() {
  group('SessionService.createSession', () {
    late FakeFirebaseFirestore ffs;
    late SessionService service;

    setUp(() {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);
    });

    test('creates session doc at sessions/{id} with correct fields', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(hostId: hostUid);

      final sessionId = await service.createSession(session: session);

      final data = await _sessionData(ffs, sessionId);
      expect(data, isNotNull);
      expect(data!['title'], equals('Test Session'));
      expect(data['hostId'], equals(hostUid));
      expect(data['subject'], equals(Subject.computerScience.name));
      expect(data['visibility'], equals(SessionVisibility.public.name));
      expect(data['capacity'], equals(10));
      expect(data['location'], equals('Room 101'));
      expect(data['reviewsEnabled'], isTrue);
    });

    test('creates host member doc at sessions/{id}/members/{hostUid} with role=host, status=active', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(hostId: hostUid, hostName: 'Alice');

      final sessionId = await service.createSession(session: session);

      final memberSnap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(hostUid)
          .get();

      expect(memberSnap.exists, isTrue);
      final mData = memberSnap.data()!;
      expect(mData['role'], equals('host'));
      expect(mData['userId'], equals(hostUid));
      expect(mData['username'], equals('Alice'));
      expect(mData['attended'], isFalse);
      expect(mData['sessionTitle'], equals('Test Session'));
      expect(mData['hostId'], equals(hostUid));
      expect(mData['sessionStatus'], equals(SessionStatus.upcoming.name));
    });

    test('participantCount starts at 1 (the host)', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(hostId: hostUid);

      final sessionId = await service.createSession(session: session);

      final data = await _sessionData(ffs, sessionId);
      // FakeFirebaseFirestore resolves FieldValue.increment to an int.
      expect(data!['participantCount'], equals(1));
    });

    test('sessionsHostedCount (sessionsCount) on user doc increments by 1', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid, sessionsCount: 3);
      final session = _makeSession(hostId: hostUid);

      await service.createSession(session: session);

      expect(await _sessionsCount(ffs, hostUid), equals(4));
    });

    test('private session: passwordHash is stored and plain password is NOT stored', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(
        hostId: hostUid,
        visibility: SessionVisibility.private,
      );

      final sessionId = await service.createSession(
        session: session,
        plainTextPassword: 'super-secret',
      );

      final data = await _sessionData(ffs, sessionId);
      expect(data, isNotNull);

      // passwordHash must be present and in "<hex>:<base64salt>" format.
      final hash = data!['passwordHash'] as String?;
      expect(hash, isNotNull);
      expect(hash, isNot(equals('super-secret')));
      final parts = hash!.split(':');
      expect(parts.length, equals(2));
      // SHA-256 hex is 64 chars.
      expect(parts[0].length, equals(64));
      // base64-encoded 16 bytes is 24 chars.
      expect(base64.decode(parts[1]).length, equals(16));
    });

    test('public session: no passwordHash field present', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(
        hostId: hostUid,
        visibility: SessionVisibility.public,
      );

      final sessionId = await service.createSession(session: session);

      final data = await _sessionData(ffs, sessionId);
      // passwordHash should be absent (null) for public sessions.
      expect(data!['passwordHash'], isNull);
    });

    test('private session without password throws DataException', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid);
      final session = _makeSession(
        hostId: hostUid,
        visibility: SessionVisibility.private,
      );

      await expectLater(
        service.createSession(session: session),
        throwsA(isA<DataException>()),
      );
    });

    test('all three batch writes happen atomically — session + member + userCount exist together', () async {
      const hostUid = 'host-uid';
      await _seedUser(ffs, hostUid, sessionsCount: 0);
      final session = _makeSession(hostId: hostUid);

      final sessionId = await service.createSession(session: session);

      // All three side effects must be observable after the call.
      final sessionData = await _sessionData(ffs, sessionId);
      final memberCount = await _memberCount(ffs, sessionId);
      final userCount = await _sessionsCount(ffs, hostUid);

      expect(sessionData, isNotNull);
      expect(memberCount, equals(1));
      expect(userCount, equals(1));
    });
  });

  // ── editSession ─────────────────────────────────────────────────────────────

  group('SessionService.editSession', () {
    late FakeFirebaseFirestore ffs;
    late SessionService service;

    setUp(() {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);
    });

    /// Seed a complete session document directly (bypass createSession).
    Future<String> seedSession(
      FakeFirebaseFirestore ffs, {
      String sessionId = 'session-1',
      String hostId = 'host-uid',
      String title = 'Original Title',
      int participantCount = 1,
    }) async {
      final now = Timestamp.fromDate(DateTime(2026, 6, 1, 10));
      await ffs.collection(FirestoreCollections.sessions).doc(sessionId).set({
        'title': title,
        'hostId': hostId,
        'subject': Subject.computerScience.name,
        'visibility': SessionVisibility.public.name,
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
      });
      return sessionId;
    }

    test('updates mutable fields on the session doc', () async {
      final sessionId = await seedSession(ffs);

      await service.editSession(
        sessionId: sessionId,
        callerUid: 'host-uid',
        updates: {'title': 'Updated Title', 'location': 'Room 202'},
      );

      final data = await _sessionData(ffs, sessionId);
      expect(data!['title'], equals('Updated Title'));
      expect(data['location'], equals('Room 202'));
    });

    test('does NOT change participantCount or hostId', () async {
      final sessionId = await seedSession(ffs, participantCount: 3, hostId: 'host-uid');

      await service.editSession(
        sessionId: sessionId,
        callerUid: 'host-uid',
        updates: {'title': 'New Title'},
      );

      final data = await _sessionData(ffs, sessionId);
      expect(data!['participantCount'], equals(3));
      expect(data['hostId'], equals('host-uid'));
    });

    test('fans out card-render changes to all member docs', () async {
      const sessionId = 'session-1';
      await seedSession(ffs, sessionId: sessionId);

      // Seed two member docs.
      for (final uid in ['host-uid', 'member-uid']) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .set({
          'userId': uid,
          'sessionTitle': 'Original Title',
          'sessionStatus': SessionStatus.upcoming.name,
        });
      }

      await service.editSession(
        sessionId: sessionId,
        callerUid: 'host-uid',
        updates: {'title': 'Renamed Session'},
        updatedCardFields: ['title'],
      );

      for (final uid in ['host-uid', 'member-uid']) {
        final snap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .get();
        expect(snap.data()!['sessionTitle'], equals('Renamed Session'),
            reason: 'member $uid should have updated sessionTitle');
      }
    });

    test('rejects edit by non-host — throws DataException', () async {
      final sessionId = await seedSession(ffs, hostId: 'host-uid');

      await expectLater(
        service.editSession(
          sessionId: sessionId,
          callerUid: 'not-the-host',
          updates: {'title': 'Malicious Title'},
        ),
        throwsA(isA<DataException>()),
      );

      // Session title must remain unchanged.
      final data = await _sessionData(ffs, sessionId);
      expect(data!['title'], equals('Original Title'));
    });
  });

  // ── cancelSession ────────────────────────────────────────────────────────────

  group('SessionService.cancelSession', () {
    late FakeFirebaseFirestore ffs;
    late SessionService service;

    const hostUid = 'host-uid';
    const member1Uid = 'member-1';
    const member2Uid = 'member-2';
    const sessionId = 'session-abc';

    Future<void> setupCancelScenario() async {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);

      final now = Timestamp.fromDate(DateTime(2026, 6, 1, 10));

      // Seed session doc.
      await ffs.collection(FirestoreCollections.sessions).doc(sessionId).set({
        'title': 'Study Group',
        'hostId': hostUid,
        'subject': Subject.mathematics.name,
        'visibility': SessionVisibility.public.name,
        'status': SessionStatus.upcoming.name,
        'participantCount': 3,
        'capacity': 10,
        'startTime': now,
        'endTime': Timestamp.fromDate(DateTime(2026, 6, 1, 12)),
        'location': 'Library',
        'description': '',
        'reviewsEnabled': true,
        'createdAt': now,
        'updatedAt': now,
        'hashtags': [],
      });

      // Seed host member doc.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.members)
          .doc(hostUid)
          .set({
        'userId': hostUid,
        'role': 'host',
        'sessionStatus': SessionStatus.upcoming.name,
      });

      // Seed two participant member docs.
      for (final uid in [member1Uid, member2Uid]) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .set({
          'userId': uid,
          'role': 'member',
          'sessionStatus': SessionStatus.upcoming.name,
        });
      }

      // Seed user docs with sessionsCount.
      await ffs.collection(FirestoreCollections.users).doc(hostUid).set({'sessionsCount': 1});
      await ffs.collection(FirestoreCollections.users).doc(member1Uid).set({'sessionsCount': 2});
      await ffs.collection(FirestoreCollections.users).doc(member2Uid).set({'sessionsCount': 1});

      // Seed two pending JoinRequest docs.
      for (final uid in ['requester-1', 'requester-2']) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.joinRequests)
            .doc(uid)
            .set({
          'userId': uid,
          'status': 'pending',
          'requestedAt': now,
        });
      }
    }

    test('session doc status set to cancelled', () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      final data = await _sessionData(ffs, sessionId);
      expect(data!['status'], equals(SessionStatus.cancelled.name));
    });

    test('every member doc sessionStatus set to cancelled', () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      for (final uid in [hostUid, member1Uid, member2Uid]) {
        final snap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .get();
        expect(
          snap.data()!['sessionStatus'],
          equals(SessionStatus.cancelled.name),
          reason: 'member $uid sessionStatus must be cancelled',
        );
      }
    });

    test('all open joinRequest docs are deleted', () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .get();
      expect(snap.docs, isEmpty,
          reason: 'all pending joinRequests should be deleted on cancel');
    });

    test("non-host members' sessionsCount is decremented", () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      expect(await _sessionsCount(ffs, member1Uid), equals(1),
          reason: 'member1 sessionsCount should go from 2 to 1');
      expect(await _sessionsCount(ffs, member2Uid), equals(0),
          reason: 'member2 sessionsCount should go from 1 to 0');
    });

    test("host's sessionsCount is NOT decremented on cancel", () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      // Host sessionsCount remains 1 (not decremented on cancel per ADR 0010).
      expect(await _sessionsCount(ffs, hostUid), equals(1),
          reason: 'host sessionsCount must NOT be decremented on cancel');
    });

    test('notification docs written to each non-host member', () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      for (final uid in [member1Uid, member2Uid]) {
        final snap = await ffs
            .collection(FirestoreCollections.users)
            .doc(uid)
            .collection(FirestoreCollections.notifications)
            .get();
        expect(snap.docs.length, equals(1),
            reason: 'member $uid should receive exactly one cancellation notification');
        expect(
          snap.docs.first.data()['type'],
          equals('sessionCancelled'),
        );
      }
    });

    test('host does NOT receive a notification on cancel (host is the canceller)', () async {
      await setupCancelScenario();

      await service.cancelSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
      );

      final snap = await ffs
          .collection(FirestoreCollections.users)
          .doc(hostUid)
          .collection(FirestoreCollections.notifications)
          .get();
      expect(snap.docs, isEmpty,
          reason: 'host should not get a cancellation notification for their own action');
    });

    test('throws DataException when session does not exist', () async {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);

      await expectLater(
        service.cancelSession(
          sessionId: 'nonexistent-session',
          hostId: hostUid,
          hostName: 'Alice',
        ),
        throwsA(isA<DataException>()),
      );
    });
  });

  // ── postponeSession ───────────────────────────────────────────────────────────

  group('SessionService.postponeSession', () {
    late FakeFirebaseFirestore ffs;
    late SessionService service;

    const hostUid = 'host-uid';
    const member1Uid = 'member-1';
    const sessionId = 'session-xyz';

    final originalStart = DateTime(2026, 6, 1, 10);
    final originalEnd = DateTime(2026, 6, 1, 12);
    final newStart = DateTime(2026, 6, 8, 10);
    final newEnd = DateTime(2026, 6, 8, 12);

    Future<void> setupPostponeScenario() async {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);

      await ffs.collection(FirestoreCollections.sessions).doc(sessionId).set({
        'title': 'Study Group',
        'hostId': hostUid,
        'subject': Subject.physics.name,
        'visibility': SessionVisibility.public.name,
        'status': SessionStatus.upcoming.name,
        'participantCount': 2,
        'capacity': 10,
        'startTime': Timestamp.fromDate(originalStart),
        'endTime': Timestamp.fromDate(originalEnd),
        'location': 'Library',
        'description': '',
        'reviewsEnabled': true,
        'createdAt': Timestamp.fromDate(originalStart),
        'updatedAt': Timestamp.fromDate(originalStart),
        'hashtags': [],
      });

      for (final uid in [hostUid, member1Uid]) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .set({
          'userId': uid,
          'role': uid == hostUid ? 'host' : 'member',
          'sessionStartTime': Timestamp.fromDate(originalStart),
          'sessionEndTime': Timestamp.fromDate(originalEnd),
          'sessionStatus': SessionStatus.upcoming.name,
        });

        await ffs
            .collection(FirestoreCollections.users)
            .doc(uid)
            .set({'sessionsCount': 1});
      }

      // Leave one pending JoinRequest — must NOT be deleted on postpone.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc('requester-1')
          .set({'userId': 'requester-1', 'status': 'pending'});
    }

    test('session doc startTime and endTime are updated', () async {
      await setupPostponeScenario();

      await service.postponeSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
        newStartTime: newStart,
        newEndTime: newEnd,
      );

      final data = await _sessionData(ffs, sessionId);
      final storedStart = (data!['startTime'] as Timestamp).toDate();
      final storedEnd = (data['endTime'] as Timestamp).toDate();
      expect(storedStart, equals(newStart));
      expect(storedEnd, equals(newEnd));
    });

    test('every member doc sessionStartTime and sessionEndTime are updated', () async {
      await setupPostponeScenario();

      await service.postponeSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
        newStartTime: newStart,
        newEndTime: newEnd,
      );

      for (final uid in [hostUid, member1Uid]) {
        final snap = await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .get();
        final mData = snap.data()!;
        final storedStart = (mData['sessionStartTime'] as Timestamp).toDate();
        final storedEnd = (mData['sessionEndTime'] as Timestamp).toDate();
        expect(storedStart, equals(newStart),
            reason: 'member $uid sessionStartTime should be updated');
        expect(storedEnd, equals(newEnd),
            reason: 'member $uid sessionEndTime should be updated');
      }
    });

    test('notification created for each member INCLUDING the host', () async {
      await setupPostponeScenario();

      await service.postponeSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
        newStartTime: newStart,
        newEndTime: newEnd,
      );

      for (final uid in [hostUid, member1Uid]) {
        final snap = await ffs
            .collection(FirestoreCollections.users)
            .doc(uid)
            .collection(FirestoreCollections.notifications)
            .get();
        expect(snap.docs.length, equals(1),
            reason: 'member $uid (including host) must get a postpone notification');
        expect(snap.docs.first.data()['type'], equals('sessionPostponed'));
      }
    });

    test('pending JoinRequest docs are left untouched on postpone', () async {
      await setupPostponeScenario();

      await service.postponeSession(
        sessionId: sessionId,
        hostId: hostUid,
        hostName: 'Alice',
        newStartTime: newStart,
        newEndTime: newEnd,
      );

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .get();
      expect(snap.docs.length, equals(1),
          reason: 'joinRequests should not be deleted on postpone per ADR 0010');
    });

    test('throws DataException when session does not exist', () async {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);

      await expectLater(
        service.postponeSession(
          sessionId: 'nonexistent',
          hostId: hostUid,
          hostName: 'Alice',
          newStartTime: newStart,
          newEndTime: newEnd,
        ),
        throwsA(isA<DataException>()),
      );
    });
  });

  // ── deleteSession ─────────────────────────────────────────────────────────────

  group('SessionService.deleteSession', () {
    late FakeFirebaseFirestore ffs;
    late SessionService service;

    const hostUid = 'host-uid';
    const member1Uid = 'member-1';
    const sessionId = 'session-del';

    Future<void> setupDeleteScenario() async {
      ffs = FakeFirebaseFirestore();
      service = SessionService(firestore: ffs);

      final now = Timestamp.fromDate(DateTime(2026, 6, 1, 10));

      await ffs.collection(FirestoreCollections.sessions).doc(sessionId).set({
        'title': 'To Be Deleted',
        'hostId': hostUid,
        'subject': Subject.biology.name,
        'visibility': SessionVisibility.public.name,
        'status': SessionStatus.upcoming.name,
        'participantCount': 2,
        'capacity': 10,
        'startTime': now,
        'endTime': Timestamp.fromDate(DateTime(2026, 6, 1, 12)),
        'location': 'Lab',
        'description': '',
        'reviewsEnabled': false,
        'createdAt': now,
        'updatedAt': now,
        'hashtags': [],
      });

      for (final uid in [hostUid, member1Uid]) {
        await ffs
            .collection(FirestoreCollections.sessions)
            .doc(sessionId)
            .collection(FirestoreCollections.members)
            .doc(uid)
            .set({'userId': uid, 'role': uid == hostUid ? 'host' : 'member'});
      }

      await ffs.collection(FirestoreCollections.users).doc(hostUid).set({'sessionsCount': 1});
      await ffs.collection(FirestoreCollections.users).doc(member1Uid).set({'sessionsCount': 2});

      // One joinRequest doc.
      await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .doc('req-1')
          .set({'userId': 'req-1', 'status': 'pending'});
    }

    test('session doc is deleted', () async {
      await setupDeleteScenario();

      await service.deleteSession(sessionId: sessionId, hostId: hostUid);

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .get();
      expect(snap.exists, isFalse);
    });

    test('member sub-collection docs are deleted', () async {
      await setupDeleteScenario();

      await service.deleteSession(sessionId: sessionId, hostId: hostUid);

      final memberCount = await _memberCount(ffs, sessionId);
      expect(memberCount, equals(0));
    });

    test('joinRequest sub-collection docs are deleted', () async {
      await setupDeleteScenario();

      await service.deleteSession(sessionId: sessionId, hostId: hostUid);

      final snap = await ffs
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .collection(FirestoreCollections.joinRequests)
          .get();
      expect(snap.docs, isEmpty);
    });

    test("non-host member's sessionsCount is decremented", () async {
      await setupDeleteScenario();

      await service.deleteSession(sessionId: sessionId, hostId: hostUid);

      expect(await _sessionsCount(ffs, member1Uid), equals(1),
          reason: 'non-host member sessionsCount should decrement from 2 to 1');
    });

    // Per ADR 0010 and service code: host sessionsCount is NOT decremented on
    // delete either — the service only decrements non-host members.
    // NOTE: This contradicts the task description which says "sessionsHostedCount decrements"
    // on deleteSession. The production code does NOT decrement for the host on delete.
    // Flagging this discrepancy — see production code issue notes in summary.
    test('host sessionsCount is NOT decremented on delete (current service behavior)', () async {
      await setupDeleteScenario();

      await service.deleteSession(sessionId: sessionId, hostId: hostUid);

      expect(await _sessionsCount(ffs, hostUid), equals(1),
          reason: 'current service code does not decrement host sessionsCount on deleteSession; '
              'see production code issue flag in test summary');
    });
  });
}
