import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/join_request.dart';
import '../models/participant.dart';

/// Handles: joining, leaving, approving/declining join requests
class ParticipationService {
  // ignore: unused_field
  final FirebaseFirestore _firestore;

  ParticipationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> joinSession({
    required String sessionId,
    required String userId,
    required String username,
    String? profilePhotoUrl,
  }) {
    throw UnimplementedError();
  }

  Future<void> requestToJoin({
    required String sessionId,
    required String userId,
    required String username,
    String? profilePhotoUrl,
  }) {
    throw UnimplementedError();
  }


  Future<void> approveRequest({
    required String sessionId,
    required String requestId,
    required String userId,
    required String username,
    String? profilePhotoUrl,
  }) {
    throw UnimplementedError();
  }

  Future<void> declineRequest({
    required String sessionId,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<void> leaveSession({
    required String sessionId,
    required String userId,
  }) {
    throw UnimplementedError();
  }


  Stream<List<Participant>> watchParticipants(String sessionId) {
    throw UnimplementedError();
  }


  Stream<List<JoinRequest>> watchJoinRequests(String sessionId) {
    throw UnimplementedError();
  }
}

final participationServiceProvider = Provider<ParticipationService>((ref) {
  return ParticipationService();
});