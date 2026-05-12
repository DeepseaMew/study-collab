// ignore_for_file: avoid_relative_lib_imports

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/features/session/screens/edit_session_screen.dart';
import 'package:study_collab/features/session/widgets/session_form.dart';
import 'package:study_collab/models/app_user.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/join_request.dart';
import 'package:study_collab/models/participant.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';
import 'package:study_collab/services/session_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppUser _makeUser({required String id, String username = 'TestUser'}) {
  final now = DateTime(2026, 1, 1);
  return AppUser(
    id: id,
    email: 'test@kmutt.ac.th',
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

Session _makeSession({required String hostId}) {
  final now = DateTime(2026, 6, 1, 10);
  return Session(
    id: 'test_session_id',
    title: 'Physics Study Group',
    subject: Subject.physics,
    description: 'Weekly physics review',
    visibility: SessionVisibility.public,
    hostId: hostId,
    hostName: 'Real Host',
    startTime: now,
    endTime: now.add(const Duration(hours: 2)),
    location: 'Library',
    capacity: 5,
    participantCount: 1,
    reviewsEnabled: true,
    createdAt: now,
    updatedAt: now,
    hashtags: const [],
  );
}

// ── A no-op SessionService so the form never hits Firestore ──────────────────

class _NoOpSessionService extends SessionService {
  _NoOpSessionService() : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<Session?> watchSession(String sessionId) => Stream.value(null);

  @override
  Future<void> editSession({
    required String sessionId,
    required String callerUid,
    required Map<String, dynamic> updates,
    List<String>? updatedCardFields,
  }) async {}
}

// ── A no-op ParticipationService ─────────────────────────────────────────────

class _NoOpParticipationService extends ParticipationService {
  _NoOpParticipationService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<Participant?> getMemberOnce({
    required String sessionId,
    required String userId,
  }) async => null;

  @override
  Future<JoinRequest?> getJoinRequestOnce({
    required String sessionId,
    required String userId,
  }) async => null;
}

// ── Pump helper ───────────────────────────────────────────────────────────────

/// Pumps [EditSessionScreen] wrapped in a GoRouter + ProviderScope.
Future<void> _pumpEditScreen(
  WidgetTester tester, {
  required Session session,
  required AppUser currentUser,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const EditSessionScreen(id: 'test_session_id'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Override the session stream to return our seeded session.
        sessionStreamProvider('test_session_id').overrideWith(
          (ref) => Stream.value(session),
        ),
        // Override the current user.
        currentUserProvider.overrideWith(
          (ref) => Stream.value(currentUser),
        ),
        // Provide no-op services so the widget never touches Firestore.
        sessionServiceProvider.overrideWithValue(_NoOpSessionService()),
        participationServiceProvider
            .overrideWithValue(_NoOpParticipationService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle(const Duration(seconds: 5));
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('EditSessionScreen — auth guard regression (Pass 2 H3)', () {
    const testSessionId = 'test_session_id';
    const realHostId = 'real_host';

    // ── Test I — non-host sees unauthorized message, not the form ─────────────

    testWidgets(
      // Regression: H3 - non-host viewing edit URL must see auth error,
      // not the form
      'I: non-host user sees unauthorized message and no SessionForm',
      (tester) async {
        final session = _makeSession(hostId: realHostId);
        final nonHostUser = _makeUser(id: 'not_host_999');

        await _pumpEditScreen(
          tester,
          session: session,
          currentUser: nonHostUser,
        );

        // Must show the unauthorized message.
        expect(
          find.text('You are not authorized to edit this session.'),
          findsOneWidget,
          reason: 'non-host must see the unauthorized message',
        );

        // Must NOT show the SessionForm.
        expect(
          find.byType(SessionForm),
          findsNothing,
          reason: 'SessionForm must not be rendered for a non-host user',
        );
      },
    );

    // ── Test J — host sees the form ───────────────────────────────────────────

    testWidgets(
      // Regression: H3 - host must see the edit form
      'J: host user sees SessionForm and no unauthorized message',
      (tester) async {
        final session = _makeSession(hostId: realHostId);
        final hostUser = _makeUser(id: realHostId);

        await _pumpEditScreen(
          tester,
          session: session,
          currentUser: hostUser,
        );

        // Must show SessionForm.
        expect(
          find.byType(SessionForm),
          findsOneWidget,
          reason: 'host must see the SessionForm',
        );

        // Must NOT show the unauthorized message.
        expect(
          find.text('You are not authorized to edit this session.'),
          findsNothing,
          reason: 'host must not see the unauthorized message',
        );
      },
    );
  });
}
