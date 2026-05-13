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

// Join / cancel action infrastructure ────────────────────────────────────────

/// Optimistic local list of sessions the user has just requested to join.
/// Merges with [myPendingSessionsProvider] in My Sessions for immediate display.
/// Cleared entry-by-entry when the user cancels or Firestore confirms.
final localPendingSessionsProvider = StateProvider<List<Session>>((ref) => []);

/// Thin action facade over [ParticipationService]. Handles the Firestore write
/// and updates local optimistic state immediately — no stream restart required.
class SessionJoinActions {
  final ParticipationService _svc;
  final Ref _ref;

  SessionJoinActions(this._svc, this._ref);

  Future<void> sendJoinRequest({
    required String sessionId,
    required String userId,
    required String username,
    String? profilePhotoUrl,
  }) async {
    await _svc.requestJoin(
      sessionId: sessionId,
      userId: userId,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
    );
    final session =
        await _ref.read(sessionServiceProvider).getSession(sessionId);
    if (session != null) {
      final current = _ref.read(localPendingSessionsProvider);
      if (!current.any((s) => s.id == sessionId)) {
        _ref.read(localPendingSessionsProvider.notifier).state = [
          ...current,
          session.copyWith(myStatus: JoinStatus.pending),
        ];
      }
    }
  }

  Future<void> cancelJoinRequest({
    required String sessionId,
    required String userId,
  }) async {
    await _svc.cancelJoinRequest(sessionId: sessionId, userId: userId);
    _ref.read(localPendingSessionsProvider.notifier).state = _ref
        .read(localPendingSessionsProvider)
        .where((s) => s.id != sessionId)
        .toList();
  }
}

final sessionJoinActionsProvider = Provider<SessionJoinActions>((ref) {
  return SessionJoinActions(ref.watch(participationServiceProvider), ref);
});

// CHANGED: pending sessions for My Sessions Upcoming tab ───────────────────────

/// Live stream of sessions where [userId] has a pending join request.
/// Fetches full session data per request then marks each as pending.
/// Sorted by requestedAt DESC (most-recent first).
final myPendingSessionsProvider = StreamProvider.family<List<Session>, String>((
  ref,
  userId,
) async* {
  final participationSvc = ref.watch(participationServiceProvider);
  final sessionSvc = ref.watch(sessionServiceProvider);

  await for (final requests in participationSvc.watchMyPendingRequests(userId)) {
    final sessions = <Session>[];
    for (final req in requests) {
      final session = await sessionSvc.getSession(req.sessionId);
      if (session != null) {
        sessions.add(session.copyWith(myStatus: JoinStatus.pending));
      }
    }
    yield sessions;
  }
});

/// Live count of the user's pending join requests — drives the Sessions nav badge.
final pendingSessionsCountProvider = StreamProvider.family<int, String>((
  ref,
  userId,
) {
  return ref
      .watch(participationServiceProvider)
      .watchMyPendingRequests(userId)
      .map((list) => list.length);
});
