import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';

/// Handles: create, read, update, delete sessions + home feed
class SessionService {
  // ignore: unused_field
  final FirebaseFirestore _firestore;

  SessionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<Session>> watchPublicSessions() {
    throw UnimplementedError();
  }


  Future<Session?> getSession(String sessionId) {
    throw UnimplementedError();
  }

  Future<String> createSession(Session session) {
    throw UnimplementedError();
  }


  Future<void> updateSession(Session session) {
    throw UnimplementedError();
  }


  Future<void> deleteSession(String sessionId) {
    throw UnimplementedError();
  }

  Stream<List<Session>> watchHostedSessions(String userId) {
    throw UnimplementedError();
  }


  Stream<List<Session>> watchJoinedSessions(String userId) {
    throw UnimplementedError();
  }
}

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService();
});