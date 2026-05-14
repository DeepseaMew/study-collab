import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/session_service.dart';

// Firestore path constants (mirrors FirestoreCollections to avoid importing
// production constants and risking accidental edits).
const _kSessions = 'sessions';
const _kUsers = 'users';
const _kMembers = 'members';
const _kJoinRequests = 'joinRequests';
const _kMessages = 'messages';
const _kGroupChat = 'groupChat';
const _kNotifications = 'notifications';

// ── Helper builders ────────────────────────────────────────────────────────────

/// Seeds a minimal user doc so createSession's batch.update(userRef, ...) succeeds.
Future<void> _seedUser(FakeFirebaseFirestore fakeFs, String uid) async {
  await fakeFs.collection(_kUsers).doc(uid).set({
    'username': 'Host One',
    'profilePhotoUrl': 'https://example.com/host.jpg',
    'sessionsCount': 0,
  });
}

/// Returns a minimal valid public [Session] suitable for passing to createSession.
/// The [id] is a placeholder — createSession ignores the model's id and
/// generates its own via `_firestore.collection(...).doc()`.
Session _buildPublicSession({String hostId = 'host1'}) {
  final now = DateTime(2026, 6, 1, 10, 0);
  return Session(
    id: 'placeholder',
    title: 'CS Study Group',
    subject: Subject.computerScience,
    description: 'Weekly CS review session',
    visibility: SessionVisibility.public,
    hostId: hostId,
    hostName: 'Host One',
    hostPhotoUrl: 'https://example.com/host.jpg',
    startTime: now,
    endTime: now.add(const Duration(hours: 2)),
    location: 'Library Room 3',
    capacity: 10,
    reviewsEnabled: true,
    createdAt: now,
    updatedAt: now,
    hashtags: const ['cs', 'algorithms'],
  );
}

/// Returns a minimal valid private [Session].
Session _buildPrivateSession({String hostId = 'host1'}) {
  final now = DateTime(2026, 6, 1, 14, 0);
  return Session(
    id: 'placeholder',
    title: 'Private Math Session',
    subject: Subject.mathematics,
    description: 'Closed study group',
    visibility: SessionVisibility.private,
    hostId: hostId,
    hostName: 'Host One',
    hostPhotoUrl: 'https://example.com/host.jpg',
    startTime: now,
    endTime: now.add(const Duration(hours: 1)),
    location: 'Room 5',
    capacity: 4,
    reviewsEnabled: false,
    createdAt: now,
    updatedAt: now,
    hashtags: const [],
  );
}

void main() {
  group('SessionService', () {
    // ── Test 1: createSession writes session doc + host member doc atomically ──

    test(
        'createSession writes session doc with correct fields and host member doc',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();

      // Act
      final sessionId = await service.createSession(session: session);

      // Assert — session doc exists with expected fields
      final sessionDoc =
          await fakeFs.collection(_kSessions).doc(sessionId).get();
      expect(sessionDoc.exists, isTrue,
          reason: 'session doc should have been created');

      final data = sessionDoc.data()!;
      expect(data['hostId'], equals('host1'));
      expect(data['title'], equals('CS Study Group'));
      expect(data['visibility'], equals('public'));
      expect(data['subject'], equals('computerScience'));
      expect(data['status'], equals('upcoming'));
      expect(data['capacity'], equals(10));
      expect(data['location'], equals('Library Room 3'));

      // Assert — host member doc exists at sessions/{id}/members/host1
      final hostMemberDoc = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .doc('host1')
          .get();
      expect(hostMemberDoc.exists, isTrue,
          reason: 'host member doc should have been created atomically');

      final memberData = hostMemberDoc.data()!;
      expect(memberData['userId'], equals('host1'));
      expect(memberData['role'], equals('host'));
      expect(memberData['sessionTitle'], equals('CS Study Group'));
      expect(memberData['hostId'], equals('host1'));

      // Assert — groupChat/meta singleton created atomically
      final groupChatMeta = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kGroupChat)
          .doc('meta')
          .get();
      expect(groupChatMeta.exists, isTrue,
          reason: 'groupChat/meta singleton must be created atomically with the session');
      expect(groupChatMeta.data()!.containsKey('lastMessageText'), isTrue);

      // Assert — host sessionsCount incremented
      final userDoc = await fakeFs.collection(_kUsers).doc('host1').get();
      expect(userDoc.data()!['sessionsCount'], equals(1),
          reason: 'sessionsCount should be incremented when host creates a session');
    });

    // ── Test 2: createSession hashes password — plaintext must NOT appear ──────

    test(
        'createSession for a private session hashes password — plaintext must not appear in Firestore',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      const plaintext = 'secret123';
      final session = _buildPrivateSession();

      // Act
      final sessionId = await service.createSession(
        session: session,
        plainTextPassword: plaintext,
      );

      // Assert — stored passwordHash is NOT the plaintext
      final data =
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).data()!;

      final storedHash = data['passwordHash'] as String?;
      expect(storedHash, isNotNull,
          reason: 'passwordHash should be set for a private session');
      expect(storedHash, isNotEmpty,
          reason: 'passwordHash should be non-empty');
      expect(storedHash, isNot(equals(plaintext)),
          reason: 'plaintext password must not be stored');
      // The hash format from _hashPassword is "<sha256hex>:<base64salt>"
      expect(storedHash!.contains(':'), isTrue,
          reason: 'hash format should be "hash:salt" containing a colon');
      // Raw password key must not appear anywhere in the doc
      expect(data.containsKey('password'), isFalse,
          reason: 'raw password field must not exist on session doc');
      expect(data.containsKey('plainTextPassword'), isFalse,
          reason: 'plainTextPassword field must not exist on session doc');
    });

    // ── Test 3: createSession for public session does NOT store a password ─────

    test(
        'createSession for a public session does not store passwordHash in Firestore',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();

      // Act
      final sessionId = await service.createSession(session: session);

      // Assert — passwordHash key is absent (null-aware map entry omits it)
      final data =
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).data()!;

      // Using null-aware map entry ('passwordHash': ?passwordHash), the key
      // is omitted entirely when null. Both absence and explicit null are safe.
      final storedHash = data['passwordHash'];
      expect(storedHash == null || storedHash == '',
          isTrue,
          reason: 'passwordHash must not be set for a public session');
    });

    // ── Test 4: editSession allows host to update session fields ───────────────

    test('editSession allows the host to update session fields', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Confirm original title
      final before =
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).data()!;
      expect(before['title'], equals('CS Study Group'));

      // Act
      await service.editSession(
        sessionId: sessionId,
        callerUid: 'host1',
        updates: {'title': 'CS Study Group — Advanced'},
      );

      // Assert — title updated in Firestore
      final after =
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).data()!;
      expect(after['title'], equals('CS Study Group — Advanced'));
    });

    // ── Test 5: editSession non-host throws DataException ─────────────────────

    test(
        'editSession throws DataException when callerUid is not the host',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Act + Assert — a different user tries to edit
      await expectLater(
        service.editSession(
          sessionId: sessionId,
          callerUid: 'not-the-host',
          updates: {'title': 'Attempted Override'},
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Only the host can edit this session',
          ),
        ),
      );
    });

    // ── Test 6: deleteSession removes session + all subcollection docs ─────────

    test(
        'deleteSession removes session doc, all member docs, all joinRequest docs, all groupChat messages, and groupChat/meta',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Seed a pending join request
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .doc('req1')
          .set({'userId': 'applicant1', 'status': 'pending'});

      // Seed a group chat message
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMessages)
          .doc('msg1')
          .set({'text': 'Hello group!', 'senderId': 'host1'});

      // Verify session exists before delete
      expect(
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).exists,
          isTrue);

      // Act
      await service.deleteSession(sessionId: sessionId, hostId: 'host1');

      // Assert — session doc gone
      expect(
          (await fakeFs.collection(_kSessions).doc(sessionId).get()).exists,
          isFalse,
          reason: 'session doc should be deleted');

      // Assert — member docs gone
      final membersAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .get();
      expect(membersAfter.docs, isEmpty,
          reason: 'all member docs should be deleted');

      // Assert — joinRequest docs gone
      final requestsAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .get();
      expect(requestsAfter.docs, isEmpty,
          reason: 'all joinRequest docs should be deleted');

      // Assert — group chat messages gone
      final messagesAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMessages)
          .get();
      expect(messagesAfter.docs, isEmpty,
          reason: 'all groupChat message docs should be deleted');

      // Assert — groupChat/meta gone
      final groupChatMetaAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kGroupChat)
          .doc('meta')
          .get();
      expect(groupChatMetaAfter.exists, isFalse,
          reason: 'groupChat/meta singleton should be deleted');
    });

    // ── Test 6: watchPublicSessions returns only public+upcoming sessions ──────

    test(
        'watchPublicSessions returns only sessions with visibility == public and status == upcoming',
        () async {
      // Arrange — seed docs directly to isolate this test from createSession
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);

      final baseTime = Timestamp.fromDate(DateTime(2026, 7, 1, 9, 0));

      // Public + upcoming — should appear
      await fakeFs.collection(_kSessions).doc('pub1').set({
        'title': 'Public Session A',
        'visibility': 'public',
        'status': 'upcoming',
        'hostId': 'host1',
        'hostName': 'Host One',
        'subject': 'computerScience',
        'description': '',
        'location': 'Room 1',
        'capacity': 5,
        'participantCount': 1,
        'reviewsEnabled': true,
        'startTime': baseTime,
        'endTime': baseTime,
        'createdAt': baseTime,
        'updatedAt': baseTime,
        'hashtags': [],
      });

      // Public + upcoming — should appear
      await fakeFs.collection(_kSessions).doc('pub2').set({
        'title': 'Public Session B',
        'visibility': 'public',
        'status': 'upcoming',
        'hostId': 'host1',
        'hostName': 'Host One',
        'subject': 'mathematics',
        'description': '',
        'location': 'Room 2',
        'capacity': 5,
        'participantCount': 1,
        'reviewsEnabled': true,
        'startTime': baseTime,
        'endTime': baseTime,
        'createdAt': baseTime,
        'updatedAt': baseTime,
        'hashtags': [],
      });

      // Private + upcoming — should NOT appear
      await fakeFs.collection(_kSessions).doc('priv1').set({
        'title': 'Private Session',
        'visibility': 'private',
        'status': 'upcoming',
        'hostId': 'host1',
        'hostName': 'Host One',
        'subject': 'physics',
        'description': '',
        'location': 'Room 3',
        'capacity': 3,
        'participantCount': 1,
        'reviewsEnabled': false,
        'startTime': baseTime,
        'endTime': baseTime,
        'createdAt': baseTime,
        'updatedAt': baseTime,
        'hashtags': [],
        'passwordHash': 'somehash:somesalt',
      });

      // Act — take the first emission from the stream
      final sessions = await service.watchPublicSessions().first;

      // Assert — exactly 2 public upcoming sessions
      expect(sessions, hasLength(2),
          reason: 'private sessions must not appear in watchPublicSessions');
      for (final s in sessions) {
        expect(s.visibility, equals(SessionVisibility.public),
            reason: 'all returned sessions must be public');
        expect(s.status, equals(SessionStatus.upcoming),
            reason: 'all returned sessions must be upcoming');
      }
    });

    // ── Test 7: error path — private session without password throws ───────────
    // Chosen because it is enforced entirely in service code (not Firestore rules),
    // making it reliably testable with FakeFirebaseFirestore.

    test(
        'createSession throws DataException when a private session has no password',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPrivateSession();

      // Act + Assert — omitting plainTextPassword for a private session
      await expectLater(
        service.createSession(session: session),
        throwsA(isA<DataException>()),
      );
    });

    // ── Bonus: editSession throws DataException for non-existent session ───────

    test(
        'editSession throws DataException when session does not exist',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);

      // Act + Assert — session 'ghost-session' was never created
      await expectLater(
        service.editSession(
          sessionId: 'ghost-session',
          callerUid: 'host1',
          updates: {'title': 'New Title'},
        ),
        throwsA(isA<DataException>()),
      );
    });

    // ── Test A: cancelSession happy path ────────────────────────────────────────

    test(
        'cancelSession marks session cancelled, decrements non-host sessionsCount, '
        'writes sessionCancelled notification to non-hosts only, deletes joinRequests',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);

      // Seed host user (sessionsCount starts at 0; createSession increments to 1).
      await _seedUser(fakeFs, 'host1');

      // Create the session via service so the session doc is fully valid for
      // Session.fromFirestore (all required fields are written by createSession).
      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Seed non-host user docs (sessionsCount: 1 — cancel decrements to 0).
      await fakeFs.collection(_kUsers).doc('member1').set({
        'username': 'Member One',
        'profilePhotoUrl': null,
        'sessionsCount': 1,
      });
      await fakeFs.collection(_kUsers).doc('member2').set({
        'username': 'Member Two',
        'profilePhotoUrl': null,
        'sessionsCount': 1,
      });

      // Seed member docs under the session (service iterates membersSnap.docs).
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .doc('member1')
          .set({'userId': 'member1', 'role': 'member', 'sessionStatus': 'upcoming'});
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .doc('member2')
          .set({'userId': 'member2', 'role': 'member', 'sessionStatus': 'upcoming'});

      // Seed one pending join request.
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .doc('req1')
          .set({'userId': 'applicant1', 'status': 'pending'});

      // Act
      await service.cancelSession(
        sessionId: sessionId,
        hostId: 'host1',
        hostName: 'Host One',
      );

      // Assert 1 — session doc is NOT deleted; status == 'cancelled'.
      final sessionDoc =
          await fakeFs.collection(_kSessions).doc(sessionId).get();
      expect(sessionDoc.exists, isTrue,
          reason: 'cancelSession must not delete the session doc');
      expect(sessionDoc.data()!['status'], equals('cancelled'),
          reason: 'session status must be set to cancelled');

      // Assert 2 — non-host sessionsCount decremented to 0.
      final member1User =
          await fakeFs.collection(_kUsers).doc('member1').get();
      expect(member1User.data()!['sessionsCount'], equals(0),
          reason: 'member1 sessionsCount must be decremented on cancel');
      final member2User =
          await fakeFs.collection(_kUsers).doc('member2').get();
      expect(member2User.data()!['sessionsCount'], equals(0),
          reason: 'member2 sessionsCount must be decremented on cancel');

      // Assert 3 — host sessionsCount unchanged (still 1 from createSession).
      final hostUser = await fakeFs.collection(_kUsers).doc('host1').get();
      expect(hostUser.data()!['sessionsCount'], equals(1),
          reason: 'host sessionsCount must NOT be decremented on cancel');

      // Assert 4 — each non-host member has exactly one sessionCancelled notification.
      for (final memberId in ['member1', 'member2']) {
        final notifs = await fakeFs
            .collection(_kUsers)
            .doc(memberId)
            .collection(_kNotifications)
            .get();
        expect(notifs.docs, hasLength(1),
            reason: '$memberId must have exactly one notification');
        expect(notifs.docs.first.data()['type'], equals('sessionCancelled'),
            reason: 'notification type must be sessionCancelled for $memberId');
      }

      // Assert 5 — host does NOT have a sessionCancelled notification.
      final hostNotifs = await fakeFs
          .collection(_kUsers)
          .doc('host1')
          .collection(_kNotifications)
          .get();
      expect(
        hostNotifs.docs
            .where((d) => d.data()['type'] == 'sessionCancelled')
            .isEmpty,
        isTrue,
        reason: 'host must not receive a sessionCancelled notification',
      );

      // Assert 6 — the join request was deleted.
      final requestsAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .get();
      expect(requestsAfter.docs, isEmpty,
          reason: 'all joinRequest docs must be deleted on cancel');
    });

    // ── Test B: cancelSession has no in-service host guard ──────────────────────

    test(
        'cancelSession does not throw when called with a wrong hostId — '
        'host identity is enforced by Firestore rules only',
        () async {
      // cancelSession enforces host identity via Firestore rules only — no in-service guard.
      //
      // Calling cancelSession with hostId: 'not-host' succeeds at the service
      // layer. The service treats 'not-host' as the "host", so all actual members
      // (including the real host1) receive the non-host treatment: sessionsCount
      // is decremented and a notification is written for every member doc.

      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Act + Assert — must not throw even though 'not-host' is not the real host.
      await expectLater(
        service.cancelSession(
          sessionId: sessionId,
          hostId: 'not-host',
          hostName: 'Not The Host',
        ),
        completes,
      );

      // Sanity: session is now cancelled.
      final sessionDoc =
          await fakeFs.collection(_kSessions).doc(sessionId).get();
      expect(sessionDoc.data()!['status'], equals('cancelled'));
    });

    // ── Test C: postponeSession happy path ──────────────────────────────────────

    test(
        'postponeSession updates session times, updates all member docs, '
        'writes sessionPostponed notification to all members including host, '
        'and does NOT delete joinRequests or change sessionsCount',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);
      await _seedUser(fakeFs, 'host1');

      final session = _buildPublicSession();
      final sessionId = await service.createSession(session: session);

      // Seed non-host user docs.
      await fakeFs.collection(_kUsers).doc('member1').set({
        'username': 'Member One',
        'profilePhotoUrl': null,
        'sessionsCount': 1,
      });
      await fakeFs.collection(_kUsers).doc('member2').set({
        'username': 'Member Two',
        'profilePhotoUrl': null,
        'sessionsCount': 1,
      });

      // Seed member docs under the session.
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .doc('member1')
          .set({'userId': 'member1', 'role': 'member', 'sessionStatus': 'upcoming'});
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kMembers)
          .doc('member2')
          .set({'userId': 'member2', 'role': 'member', 'sessionStatus': 'upcoming'});

      // Seed one pending join request (must survive postponeSession).
      await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .doc('req1')
          .set({'userId': 'applicant1', 'status': 'pending'});

      final newStart = DateTime(2026, 7, 15, 10, 0);
      final newEnd = DateTime(2026, 7, 15, 12, 0);

      // Act
      await service.postponeSession(
        sessionId: sessionId,
        hostId: 'host1',
        hostName: 'Host One',
        newStartTime: newStart,
        newEndTime: newEnd,
      );

      // Assert 1 — session doc startTime and endTime are updated.
      final sessionDoc =
          await fakeFs.collection(_kSessions).doc(sessionId).get();
      expect(
        sessionDoc.data()!['startTime'],
        equals(Timestamp.fromDate(newStart)),
        reason: 'session startTime must be updated to newStartTime',
      );
      expect(
        sessionDoc.data()!['endTime'],
        equals(Timestamp.fromDate(newEnd)),
        reason: 'session endTime must be updated to newEndTime',
      );

      // Assert 2 — every member doc (host1, member1, member2) has updated times.
      for (final memberId in ['host1', 'member1', 'member2']) {
        final memberDoc = await fakeFs
            .collection(_kSessions)
            .doc(sessionId)
            .collection(_kMembers)
            .doc(memberId)
            .get();
        expect(memberDoc.exists, isTrue,
            reason: '$memberId member doc must still exist');
        expect(
          memberDoc.data()!['sessionStartTime'],
          equals(Timestamp.fromDate(newStart)),
          reason: '$memberId sessionStartTime must be updated',
        );
        expect(
          memberDoc.data()!['sessionEndTime'],
          equals(Timestamp.fromDate(newEnd)),
          reason: '$memberId sessionEndTime must be updated',
        );
      }

      // Assert 3 — every member (host1, member1, member2) has one sessionPostponed notification.
      for (final memberId in ['host1', 'member1', 'member2']) {
        final notifs = await fakeFs
            .collection(_kUsers)
            .doc(memberId)
            .collection(_kNotifications)
            .get();
        expect(notifs.docs, hasLength(1),
            reason: '$memberId must have exactly one notification');
        expect(notifs.docs.first.data()['type'], equals('sessionPostponed'),
            reason: 'notification type must be sessionPostponed for $memberId');
      }

      // Assert 4 — the join request is still present (postponeSession must not delete it).
      final requestsAfter = await fakeFs
          .collection(_kSessions)
          .doc(sessionId)
          .collection(_kJoinRequests)
          .get();
      expect(requestsAfter.docs, hasLength(1),
          reason: 'postponeSession must NOT delete joinRequest docs');

      // Assert 5 — no sessionsCount fields were changed.
      final hostUser = await fakeFs.collection(_kUsers).doc('host1').get();
      expect(hostUser.data()!['sessionsCount'], equals(1),
          reason: 'host sessionsCount must not change on postpone');
      final member1User =
          await fakeFs.collection(_kUsers).doc('member1').get();
      expect(member1User.data()!['sessionsCount'], equals(1),
          reason: 'member1 sessionsCount must not change on postpone');
      final member2User =
          await fakeFs.collection(_kUsers).doc('member2').get();
      expect(member2User.data()!['sessionsCount'], equals(1),
          reason: 'member2 sessionsCount must not change on postpone');
    });

    // ── Test D: postponeSession throws for non-existent session ────────────────

    test(
        'postponeSession throws DataException when session does not exist',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = SessionService(firestore: fakeFs);

      final newStart = DateTime(2026, 8, 1, 9, 0);
      final newEnd = DateTime(2026, 8, 1, 11, 0);

      // Act + Assert — 'ghost-session' was never created.
      await expectLater(
        service.postponeSession(
          sessionId: 'ghost-session',
          hostId: 'host1',
          hostName: 'Host One',
          newStartTime: newStart,
          newEndTime: newEnd,
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            'Session not found',
          ),
        ),
      );
    });
  });
}
