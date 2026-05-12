import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/join_request.dart';
import 'package:study_collab/models/participant.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';
import 'package:study_collab/services/session_service.dart';

/// Streams a single session document in real time, with [Session.myStatus]
/// computed from the members and joinRequests subcollections.
///
/// Emits null if the session does not exist.
final sessionStreamProvider = StreamProvider.family<Session?, String>((
  ref,
  sessionId,
) {
  final me = ref.watch(currentUserProvider).asData?.value;
  return ref.watch(sessionServiceProvider).watchSession(sessionId).asyncMap((
    session,
  ) async {
    if (session == null || me == null) return session;
    JoinStatus status;
    if (session.hostId == me.id) {
      status = JoinStatus.host;
    } else {
      final memberDoc = await ref
          .read(participationServiceProvider)
          .getMemberOnce(sessionId: sessionId, userId: me.id);
      if (memberDoc != null) {
        status = JoinStatus.joined;
      } else {
        final requestDoc = await ref
            .read(participationServiceProvider)
            .getJoinRequestOnce(sessionId: sessionId, userId: me.id);
        status = requestDoc != null ? JoinStatus.pending : JoinStatus.notJoined;
      }
    }
    return session.copyWith(myStatus: status);
  });
});

/// Streams all members of a session in real time.
final sessionMembersProvider = StreamProvider.family<List<Participant>, String>(
  (ref, sessionId) {
    return ref
        .watch(participationServiceProvider)
        .watchSessionMembers(sessionId);
  },
);

/// Streams all pending join requests for a session in real time.
///
/// Requires the current user to be the host — the service returns an empty
/// stream immediately if [callerUid] does not match the session's hostId,
/// preventing non-hosts from receiving raw Firestore permission-denied errors.
final sessionRequestsProvider =
    StreamProvider.family<List<JoinRequest>, String>((ref, sessionId) {
      final me = ref.watch(currentUserProvider).asData?.value;
      if (me == null) return Stream.value(<JoinRequest>[]);
      return ref
          .watch(participationServiceProvider)
          .watchPendingRequests(sessionId, callerUid: me.id);
    });
