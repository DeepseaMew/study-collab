import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../models/session.dart';
import '../../../services/participation_service.dart';
import '../../../services/session_service.dart';
import '../../auth/providers/auth_providers.dart';

/// Dashboard "discover" feed — public sessions visible to all users.
///
/// Reads live data from Firestore via sessionService.watchPublicSessions.
/// Combines that with the current user's membership + pending requests
/// so each Session has its correct myStatus (notJoined / pending /
/// joined / host).
///
/// Returns an `AsyncValue<List<Session>>` so the UI can show loading and
/// error states naturally. Until the user is signed in, returns an
/// empty list.
final dashboardSessionsProvider = StreamProvider<List<Session>>((ref) async* {
  // Watch the current user; once signed in we can compute myStatus.
  final me = ref.watch(currentUserProvider).asData?.value;
  if (me == null) {
    yield <Session>[];
    return;
  }

  final sessionService = ref.watch(sessionServiceProvider);
  final participationService = ref.watch(participationServiceProvider);

  // Watch all public upcoming sessions live.
  await for (final sessions in sessionService.watchPublicSessions()) {
    final enriched = <Session>[];
    for (final s in sessions) {
      JoinStatus status;
      if (s.hostId == me.id) {
        status = JoinStatus.host;
      } else {
        // Check membership first (cheap most-common case).
        final member = await participationService.getMemberOnce(
          sessionId: s.id,
          userId: me.id,
        );
        if (member != null) {
          status = JoinStatus.joined;
        } else {
          // Check for a pending join request.
          final request = await participationService.getJoinRequestOnce(
            sessionId: s.id,
            userId: me.id,
          );
          status = request != null ? JoinStatus.pending : JoinStatus.notJoined;
        }
      }
      enriched.add(s.copyWith(myStatus: status));
    }
    yield enriched;
  }
});

/// Unread notification count for the dashboard bell badge.
///
/// TODO: wire to notification_service when implemented.
/// Hardcoded to 0 for now.
final unreadNotificationCountProvider = Provider<int>((ref) => 0);
final hostedSessionsProvider = StreamProvider.family<List<Session>, String>((
  ref,
  userId,
) {
  return ref
      .watch(sessionServiceProvider)
      .watchHostedSessions(userId)
      .map((sessions) =>
          sessions.map((s) => s.copyWith(myStatus: JoinStatus.host)).toList());
});

/// Live stream of sessions the current user is a member of (not host).
/// Maps Participant card-render fields to Session stubs for card rendering.
///
/// Hosts appear in [hostedSessionsProvider], so this provider filters them out
/// with `p.isHost == false`.
final myMembershipsProvider = StreamProvider.family<List<Session>, String>((
  ref,
  userId,
) {
  return ref
      .watch(participationServiceProvider)
      .watchUserMemberships(userId)
      .map(
        (participants) => participants
            .where((p) => !p.isHost)
            .map(
              (p) => Session(
                id: p.sessionId,
                title: p.sessionTitle,
                subject: p.sessionSubject,
                hostId: p.hostId,
                hostName: '',
                startTime: p.sessionStartTime,
                endTime: p.sessionEndTime,
                location: '',
                capacity: 0,
                status: p.sessionStatus,
                createdAt: p.joinedAt,
                updatedAt: p.joinedAt,
                myStatus: JoinStatus.joined,
              ),
            )
            .toList(),
      );
});

/// All sessions the current user has any relationship with — hosted OR joined.
/// Used by Calendar screen to mark relevant days.
/// De-duplicates by session ID.
final myCalendarSessionsProvider = Provider<List<Session>>((ref) {
  final me = ref.watch(currentUserProvider).asData?.value;
  if (me == null) return const [];
  final hosted =
      ref.watch(hostedSessionsProvider(me.id)).asData?.value ?? const [];
  final joined =
      ref.watch(myMembershipsProvider(me.id)).asData?.value ?? const [];
  final byId = <String, Session>{};
  for (final s in [...hosted, ...joined]) {
    byId[s.id] = s;
  }
  return byId.values.toList();
});
