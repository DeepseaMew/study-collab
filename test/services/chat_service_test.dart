import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/services/chat_service.dart';

// Firestore path constants (mirrors FirestoreCollections to avoid importing
// production constants here and risking accidental edits).
const _kChats = 'chats';
const _kFriends = 'friends';
const _kMessages = 'messages';
const _kUsers = 'users';

/// Seeds minimal user docs so getOrCreateDm can read username / profilePhotoUrl.
Future<void> _seedUsers(FakeFirebaseFirestore fakeFs) async {
  await fakeFs.collection(_kUsers).doc('userA').set({
    'username': 'Alice',
    'profilePhotoUrl': 'https://example.com/alice.jpg',
  });
  await fakeFs.collection(_kUsers).doc('userB').set({
    'username': 'Bob',
    'profilePhotoUrl': 'https://example.com/bob.jpg',
  });
}

/// Seeds a friendship doc so _assertFriends passes for userA → userB.
Future<void> _seedFriendship(FakeFirebaseFirestore fakeFs) async {
  await fakeFs
      .collection(_kFriends)
      .doc('userA')
      .collection('userFriends')
      .doc('userB')
      .set({'since': Timestamp.now()});
}

/// Deletes the friendship doc to simulate unfriending.
Future<void> _deleteFriendship(FakeFirebaseFirestore fakeFs) async {
  await fakeFs
      .collection(_kFriends)
      .doc('userA')
      .collection('userFriends')
      .doc('userB')
      .delete();
}

void main() {
  group('ChatService', () {
    // ── Test 1: dmId sorts uid pair ──────────────────────────────────────────

    test('dmId returns alphabetically sorted uid pair joined by underscore', () {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);

      // Act
      final idAB = service.dmId('userA', 'userB');
      final idBA = service.dmId('userB', 'userA');

      // Assert
      expect(idAB, equals('userA_userB'));
      expect(idBA, equals('userA_userB'),
          reason: 'dmId must be symmetric — order of arguments must not matter');
      expect(idAB, equals(idBA));
    });

    // ── Test 2: getOrCreateDm creates chat doc with correct fields ───────────

    test('getOrCreateDm creates chats doc containing participantIds, lastMessageAt and createdAt', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);
      await _seedUsers(fakeFs);
      await _seedFriendship(fakeFs);

      // Act
      final returnedId = await service.getOrCreateDm(
        currentUserId: 'userA',
        otherUserId: 'userB',
      );

      // Assert: returned id must match dmId
      expect(returnedId, equals(service.dmId('userA', 'userB')));

      final chatDoc = await fakeFs.collection(_kChats).doc(returnedId).get();
      expect(chatDoc.exists, isTrue, reason: 'chats doc should have been created');

      final data = chatDoc.data()!;
      expect(data.containsKey('participantIds'), isTrue);
      expect((data['participantIds'] as List).toSet(),
          equals({'userA', 'userB'}));
      expect(data.containsKey('lastMessageAt'), isTrue);
      expect(data.containsKey('createdAt'), isTrue);
    });

    // ── Test 3: Regression — getOrCreateDm does not overwrite lastMessageAt ──

    test(
        // Regression: lastMessageAt was being reset on every call
        'getOrCreateDm does NOT overwrite lastMessageAt on second call',
        () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);
      await _seedUsers(fakeFs);
      await _seedFriendship(fakeFs);

      // Act — first call creates the doc
      final id = await service.getOrCreateDm(
        currentUserId: 'userA',
        otherUserId: 'userB',
      );

      final afterFirstCall = (await fakeFs.collection(_kChats).doc(id).get())
          .data()!['lastMessageAt'];

      // Act — second call should be a no-op
      await service.getOrCreateDm(
        currentUserId: 'userA',
        otherUserId: 'userB',
      );

      final afterSecondCall = (await fakeFs.collection(_kChats).doc(id).get())
          .data()!['lastMessageAt'];

      // Assert: the timestamp stored after call 2 must equal what was stored after call 1
      expect(afterSecondCall, equals(afterFirstCall),
          reason: 'Second getOrCreateDm call must not overwrite lastMessageAt');
    });

    // ── Test 4: getOrCreateDm throws DataException for non-friends ──────────

    test('getOrCreateDm throws DataException when users are not friends', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);
      await _seedUsers(fakeFs);
      // Intentionally do NOT seed a friendship doc.

      // Act + Assert
      expect(
        () => service.getOrCreateDm(
          currentUserId: 'userA',
          otherUserId: 'userB',
        ),
        throwsA(isA<DataException>()),
      );
    });

    // ── Test 5: sendDmMessage writes message and increments unread count ──────

    test('sendDmMessage writes a message doc and increments unreadCount for recipient', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);
      await _seedUsers(fakeFs);
      await _seedFriendship(fakeFs);

      final conversationId = await service.getOrCreateDm(
        currentUserId: 'userA',
        otherUserId: 'userB',
      );

      // Verify initial unread count is 0
      final beforeSend =
          (await fakeFs.collection(_kChats).doc(conversationId).get()).data()!;
      expect(beforeSend['unreadCount_userB'], equals(0));

      // Act
      await service.sendDmMessage(
        conversationId: conversationId,
        senderId: 'userA',
        senderName: 'Alice',
        senderPhotoUrl: 'https://example.com/alice.jpg',
        text: 'Hello Bob!',
      );

      // Assert: a message doc exists in the subcollection
      final msgSnap = await fakeFs
          .collection(_kChats)
          .doc(conversationId)
          .collection(_kMessages)
          .get();
      expect(msgSnap.docs, hasLength(1),
          reason: 'Exactly one message should have been written');
      expect(msgSnap.docs.first.data()['text'], equals('Hello Bob!'));
      expect(msgSnap.docs.first.data()['senderId'], equals('userA'));

      // Assert: recipient's unread counter incremented to 1
      final afterSend =
          (await fakeFs.collection(_kChats).doc(conversationId).get()).data()!;
      expect(afterSend['unreadCount_userB'], equals(1));
    });

    // ── Test 6: sendDmMessage throws DataException after friendship revoked ───

    test('sendDmMessage throws DataException when friendship has been revoked', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);
      await _seedUsers(fakeFs);
      await _seedFriendship(fakeFs);

      final conversationId = await service.getOrCreateDm(
        currentUserId: 'userA',
        otherUserId: 'userB',
      );

      // Simulate unfriending
      await _deleteFriendship(fakeFs);

      // Act + Assert
      expect(
        () => service.sendDmMessage(
          conversationId: conversationId,
          senderId: 'userA',
          senderName: 'Alice',
          text: 'This should fail',
        ),
        throwsA(isA<DataException>()),
      );
    });

    // ── Test 7: markDmRead resets unread count to 0 ───────────────────────────

    test('markDmRead resets unreadCount for the specified user to 0', () async {
      // Arrange
      final fakeFs = FakeFirebaseFirestore();
      final service = ChatService(firestore: fakeFs);

      // Seed a chat doc directly with unreadCount_userA == 3
      const conversationId = 'userA_userB';
      await fakeFs.collection(_kChats).doc(conversationId).set({
        'participantIds': ['userA', 'userB'],
        'lastMessageText': 'Hey',
        'lastMessageAt': Timestamp.now(),
        'lastMessageSenderId': 'userB',
        'unreadCount_userA': 3,
        'unreadCount_userB': 0,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      // Act
      await service.markDmRead(
        conversationId: conversationId,
        userId: 'userA',
      );

      // Assert
      final doc =
          await fakeFs.collection(_kChats).doc(conversationId).get();
      expect(doc.data()!['unreadCount_userA'], equals(0));
    });
  });
}
