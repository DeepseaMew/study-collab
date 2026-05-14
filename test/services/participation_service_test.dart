import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';

// ── Firestore path constants ───────────────────────────────────────────────────
// Mirrors FirestoreCollections to avoid importing production constants here.
const _kSessions = 'sessions';
const _kUsers = 'users';
const _kMembers = 'members';
const _kJoinRequests = 'joinRequests';

// ── Known password triple ──────────────────────────────────────────────────────
// Pre-computed hash that matches _hashPassword logic in participation_service.dart:
//   format: "<sha256hex>:<base64salt>"
//   algorithm: sha256(saltBytes + utf8(plaintext))
//
// Generated deterministically below — never hand-written so it stays in sync
// with the production _verifyPassword implementation.
//
// Plaintext: 'hunter2'
// Salt bytes (16 bytes): [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
const _kTestPlaintext = 'hunter2';
final _kTestSaltBytes = Uint8List.fromList(
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
);

/// Builds the stored hash string in the same format as ParticipationService._verifyPassword.
/// This runs at test startup — not at compile time — which is fine for a unit test.
String _buildKnownHash() {
  final saltBytes = _kTestSaltBytes;
  final passwordBytes = utf8.encode(_kTestPlaintext);
  final combined = Uint8List(saltBytes.length + passwordBytes.length)
    ..setRange(0, saltBytes.length, saltBytes)
    ..setRange(saltBytes.length, saltBytes.length + passwordBytes.length, passwordBytes);
  final digest = sha256.convert(combined);
  final base64Salt = base64.encode(saltBytes);
  return '${digest.toString()}:$base64Salt';
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Seeds a minimal user doc so batch.update(userRef, ...) succeeds in fake Firestore.
Future<void> _seedUser(
  FakeFirebaseFirestore fakeFs,
  String uid, {
  int sessionsCount = 0,
}) async {
  await fakeFs.collection(_kUsers).doc(uid).set({
    'username': uid == 'host1' ? 'Host One' : 'User One',
    'profilePhotoUrl': 'https://example.com/$uid.jpg',
    'sessionsCount': sessionsCount,
    'friendsCount': 0,
  });
}

/// Seeds a minimal session doc and returns the [Session] model for use in service calls.
/// The [participantCount] defaults to 1 (host already counted).
Future<Session> _seedSession(
  FakeFirebaseFirestore fakeFs, {
  String sessionId = 'session1',
  String hostId = 'host1',
  int participantCount = 1,
  String? passwordHash,
  SessionVisibility visibility = SessionVisibility.public,
}) async {
  final now = DateTime(2026, 6, 1, 10, 0);
  final data = <String, dynamic>{
    'title': 'CS Study Group',
    'subject': Subject.computerScience.name,
    'description': 'Weekly CS review session',
    'visibility': visibility.name,
    'hostId': hostId,
    'hostName': 'Host One',
    'hostPhotoUrl': 'https://example.com/host.jpg',
    'startTime': Timestamp.fromDate(now),
    'endTime': Timestamp.fromDate(now.add(const Duration(hours: 2))),
    'location': 'Library Room 3',
    'capacity': 10,
    'participantCount': participantCount,
    'status': SessionStatus.upcoming.name,
    'reviewsEnabled': true,
    'createdAt': Timestamp.fromDate(now),
    'updatedAt': Timestamp.fromDate(now),
    'hashtags': <String>[],
    'passwordHash': ?passwordHash,
  };

  await fakeFs.collection(_kSessions).doc(sessionId).set(data);

  return Session(
    id: sessionId,
    title: 'CS Study Group',
    subject: Subject.computerScience,
    description: 'Weekly CS review session',
    visibility: visibility,
    hostId: hostId,
    hostName: 'Host One',
    hostPhotoUrl: 'https://example.com/host.jpg',
    startTime: now,
    endTime: now.add(const Duration(hours: 2)),
    location: 'Library Room 3',
    capacity: 10,
    participantCount: participantCount,
    status: SessionStatus.upcoming,
    reviewsEnabled: true,
    createdAt: now,
    updatedAt: now,
    passwordHash: passwordHash,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ParticipationService', () {
    // ── Test 1: requestJoin — happy path ─────────────────────────────────────

    test(
        'requestJoin creates joinRequests/{userId} doc with correct fields '
        'and status == pending', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');
      await _seedSession(fakeFs);

      // Act
      await service.requestJoin(
        sessionId: 'session1',
        userId: 'user1',
        username: 'User One',
        profilePhotoUrl: 'https://example.com/u.jpg',
      );

      // Assert
      final snap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kJoinRequests)
          .doc('user1')
          .get();

      expect(snap.exists, isTrue,
          reason: 'joinRequests/user1 doc must exist after requestJoin');

      final data = snap.data()!;
      expect(data['userId'], equals('user1'));
      expect(data['username'], equals('User One'));
      expect(data['profilePhotoUrl'], equals('https://example.com/u.jpg'));
      expect(data['status'], equals('pending'));
      expect(data.containsKey('requestedAt'), isTrue,
          reason: 'requestedAt must be present (FieldValue.serverTimestamp())');
      expect(data['respondedAt'], isNull,
          reason: 'respondedAt must be null on a fresh request');
    });

    // ── Test 2: requestJoin — duplicate throws DataException ─────────────────

    test(
        'requestJoin throws DataException with correct message when a pending '
        'request already exists for the same user + session', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');
      await _seedSession(fakeFs);

      // Seed an existing pending request doc (doc id == userId, deterministic)
      await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kJoinRequests)
          .doc('user1')
          .set({
        'userId': 'user1',
        'username': 'User One',
        'profilePhotoUrl': null,
        'status': 'pending',
        'requestedAt': Timestamp.now(),
        'respondedAt': null,
      });

      // Act + Assert
      await expectLater(
        service.requestJoin(
          sessionId: 'session1',
          userId: 'user1',
          username: 'User One',
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Request already pending for this session',
          ),
        ),
      );
    });

    // ── Test 3: approveRequest — atomic batch (all state) ────────────────────

    test(
        'approveRequest deletes request doc, creates member doc with all '
        'denormalized fields, increments participantCount, and increments '
        'user sessionsCount atomically', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);

      // Seed user docs (host + the user being approved)
      await _seedUser(fakeFs, 'host1');
      await _seedUser(fakeFs, 'user1', sessionsCount: 2);

      // Seed session with participantCount == 2
      final session = await _seedSession(fakeFs, participantCount: 2);

      // Seed pending join request for user1
      await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kJoinRequests)
          .doc('user1')
          .set({
        'userId': 'user1',
        'username': 'User One',
        'profilePhotoUrl': 'https://example.com/user1.jpg',
        'status': 'pending',
        'requestedAt': Timestamp.now(),
        'respondedAt': null,
      });

      // Act
      await service.approveRequest(
        session: session,
        callerUid: 'host1',
        requestUserId: 'user1',
        requestUsername: 'User One',
        requestUserPhotoUrl: 'https://example.com/user1.jpg',
      );

      // Assert 1 — joinRequest doc is deleted
      final requestSnap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kJoinRequests)
          .doc('user1')
          .get();
      expect(requestSnap.exists, isFalse,
          reason: 'joinRequests/user1 must be deleted after approveRequest');

      // Assert 2 — member doc exists with correct fields
      final memberSnap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kMembers)
          .doc('user1')
          .get();
      expect(memberSnap.exists, isTrue,
          reason: 'sessions/session1/members/user1 must exist after approval');

      final memberData = memberSnap.data()!;
      expect(memberData['userId'], equals('user1'));
      expect(memberData['username'], equals('User One'));
      expect(memberData['role'], equals('member'));
      expect(memberData.containsKey('joinedAt'), isTrue,
          reason: 'joinedAt must be set (FieldValue.serverTimestamp())');
      expect(memberData['attended'], equals(false));
      // Denormalized card-render fields (ADR 0008)
      expect(memberData['sessionTitle'], equals('CS Study Group'));
      expect(memberData.containsKey('sessionStartTime'), isTrue);
      expect(memberData.containsKey('sessionEndTime'), isTrue);
      expect(memberData['sessionStatus'], equals(SessionStatus.upcoming.name));
      expect(memberData['sessionSubject'], equals(Subject.computerScience.name));
      expect(memberData['hostId'], equals('host1'));

      // Assert 3 — participantCount incremented from 2 to 3
      final sessionSnap = await fakeFs.collection(_kSessions).doc('session1').get();
      expect(sessionSnap.data()!['participantCount'], equals(3),
          reason: 'participantCount must be incremented from 2 to 3');

      // Assert 4 — user sessionsCount incremented from 2 to 3
      final userSnap = await fakeFs.collection(_kUsers).doc('user1').get();
      expect(userSnap.data()!['sessionsCount'], equals(3),
          reason: 'user1 sessionsCount must be incremented from 2 to 3');
    });

    // ── Test 4: approveRequest — non-host caller throws DataException ─────────

    test(
        'approveRequest throws DataException when callerUid is not the session host',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);

      await _seedUser(fakeFs, 'host1');
      // Seed session with hostId = 'host1'
      final session = await _seedSession(fakeFs);

      // Act + Assert — caller is 'nothost', not 'host1'
      await expectLater(
        service.approveRequest(
          session: session,
          callerUid: 'nothost',
          requestUserId: 'user1',
          requestUsername: 'User One',
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Only the host can approve requests',
          ),
        ),
      );
    });

    // ── Test 5: joinWithPassword — wrong password ─────────────────────────────

    test(
        'joinWithPassword throws DataException("Incorrect password") and does '
        'not write any docs when the password is wrong', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);

      final knownHash = _buildKnownHash();

      await _seedUser(fakeFs, 'host1');
      await _seedUser(fakeFs, 'user1');

      // Seed private session with the known hash
      final session = await _seedSession(
        fakeFs,
        visibility: SessionVisibility.private,
        passwordHash: knownHash,
      );

      // Act + Assert
      await expectLater(
        service.joinWithPassword(
          session: session,
          userId: 'user1',
          username: 'User One',
          plainTextPassword: 'wrong-password',
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Incorrect password',
          ),
        ),
      );

      // Assert — no member doc written
      final memberSnap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kMembers)
          .doc('user1')
          .get();
      expect(memberSnap.exists, isFalse,
          reason: 'member doc must NOT be created when password is wrong');

      // Assert — counters unchanged
      final sessionSnap = await fakeFs.collection(_kSessions).doc('session1').get();
      expect(sessionSnap.data()!['participantCount'], equals(1),
          reason: 'participantCount must not change on wrong password');

      final userSnap = await fakeFs.collection(_kUsers).doc('user1').get();
      expect(userSnap.data()!['sessionsCount'], equals(0),
          reason: 'sessionsCount must not change on wrong password');
    });

    // ── Test 6: joinWithPassword — correct password atomic batch ─────────────

    test(
        'joinWithPassword with correct password creates member doc, '
        'increments participantCount, and increments user sessionsCount '
        'atomically', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);

      final knownHash = _buildKnownHash();

      await _seedUser(fakeFs, 'host1');
      await _seedUser(fakeFs, 'user1', sessionsCount: 0);

      // Seed private session with the known hash and participantCount == 1 (host only)
      final session = await _seedSession(
        fakeFs,
        participantCount: 1,
        visibility: SessionVisibility.private,
        passwordHash: knownHash,
      );

      // Act — provide the correct plaintext password
      await service.joinWithPassword(
        session: session,
        userId: 'user1',
        username: 'User One',
        profilePhotoUrl: 'https://example.com/user1.jpg',
        plainTextPassword: _kTestPlaintext,
      );

      // Assert 1 — member doc exists
      final memberSnap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kMembers)
          .doc('user1')
          .get();
      expect(memberSnap.exists, isTrue,
          reason: 'sessions/session1/members/user1 must exist after joinWithPassword');

      final memberData = memberSnap.data()!;
      expect(memberData['userId'], equals('user1'));
      expect(memberData['username'], equals('User One'));
      expect(memberData['role'], equals('member'));
      expect(memberData['attended'], equals(false));
      // Denormalized fields
      expect(memberData['sessionTitle'], equals('CS Study Group'));
      expect(memberData['hostId'], equals('host1'));

      // Assert 2 — participantCount incremented from 1 to 2
      final sessionSnap = await fakeFs.collection(_kSessions).doc('session1').get();
      expect(sessionSnap.data()!['participantCount'], equals(2),
          reason: 'participantCount must be incremented from 1 to 2');

      // Assert 3 — user sessionsCount incremented from 0 to 1
      final userSnap = await fakeFs.collection(_kUsers).doc('user1').get();
      expect(userSnap.data()!['sessionsCount'], equals(1),
          reason: 'user1 sessionsCount must be incremented from 0 to 1');
    });

    // ── Test 7: leaveSession — host trying to leave throws DataException ──────

    test(
        'leaveSession throws DataException and makes no writes when the member '
        'doc has role == host', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ParticipationService(firestore: fakeFs);

      await _seedUser(fakeFs, 'host1', sessionsCount: 1);
      await _seedSession(fakeFs, participantCount: 1);

      // Seed the host member doc
      await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kMembers)
          .doc('host1')
          .set({
        'userId': 'host1',
        'username': 'Host One',
        'profilePhotoUrl': 'https://example.com/host1.jpg',
        'role': 'host',
        'joinedAt': Timestamp.now(),
        'attended': false,
        'sessionTitle': 'CS Study Group',
        'sessionStartTime': Timestamp.now(),
        'sessionEndTime': Timestamp.now(),
        'sessionStatus': 'upcoming',
        'sessionSubject': 'computerScience',
        'hostId': 'host1',
      });

      // Act + Assert
      await expectLater(
        service.leaveSession(sessionId: 'session1', userId: 'host1'),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Hosts cannot leave their own session. Cancel the session instead.',
          ),
        ),
      );

      // Assert — member doc still exists (no writes happened)
      final memberSnap = await fakeFs
          .collection(_kSessions)
          .doc('session1')
          .collection(_kMembers)
          .doc('host1')
          .get();
      expect(memberSnap.exists, isTrue,
          reason: 'host member doc must still exist after rejected leaveSession');

      // Assert — counters unchanged
      final sessionSnap = await fakeFs.collection(_kSessions).doc('session1').get();
      expect(sessionSnap.data()!['participantCount'], equals(1),
          reason: 'participantCount must not change when host tries to leave');

      final userSnap = await fakeFs.collection(_kUsers).doc('host1').get();
      expect(userSnap.data()!['sessionsCount'], equals(1),
          reason: 'host sessionsCount must not change when leaveSession is rejected');
    });
  });
}
