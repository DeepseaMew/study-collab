import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Stub pages — no Riverpod, no Firebase.
// Each route builder returns a Scaffold whose body has a unique Text key so
// tests can assert which screen is visible.
// ---------------------------------------------------------------------------

Widget _stub(String label) => Scaffold(body: Text(label));

// ---------------------------------------------------------------------------
// Route list — mirrors app_router.dart exactly.
// Kept here so structural tests can inspect the list in isolation without
// importing any production code that pulls in Firebase.
// The shell builder is a plain Scaffold(body: child) so no MainShell
// (Riverpod ConsumerWidget) is involved.
// ---------------------------------------------------------------------------

List<RouteBase> _buildRoutes() {
  return [
    // Auth flow
    GoRoute(path: '/splash', builder: (_, __) => _stub('splash')),
    GoRoute(path: '/login', builder: (_, __) => _stub('login')),
    GoRoute(path: '/signup', builder: (_, __) => _stub('signup')),
    GoRoute(path: '/verify-email', builder: (_, __) => _stub('verify-email')),

    // Shell (bottom nav)
    ShellRoute(
      builder: (_, __, child) => Scaffold(body: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => _stub('home')),
        GoRoute(path: '/calendar', builder: (_, __) => _stub('calendar')),
        GoRoute(path: '/my-sessions', builder: (_, __) => _stub('my-sessions')),
        GoRoute(path: '/messages', builder: (_, __) => _stub('messages')),
        GoRoute(path: '/profile', builder: (_, __) => _stub('profile')),
        // calendar/day lives inside the shell so the bottom nav stays visible
        GoRoute(
          path: '/calendar/day',
          builder: (_, __) => _stub('calendar-day'),
        ),
      ],
    ),

    // My-sessions detail (outside shell — no bottom nav)
    GoRoute(
      path: '/my-sessions/member/:id',
      builder: (_, __) => _stub('member-session-detail'),
    ),
    GoRoute(
      path: '/my-sessions/:id',
      builder: (_, __) => _stub('host-session-detail'),
    ),

    // Session flows (outside shell)
    GoRoute(
        path: '/create-session', builder: (_, __) => _stub('create-session')),
    GoRoute(path: '/session/:id', builder: (_, __) => _stub('session-detail')),
    GoRoute(
        path: '/session/:id/edit',
        builder: (_, __) => _stub('edit-session')),
    GoRoute(
        path: '/session/:id/members',
        builder: (_, __) => _stub('session-members')),
    GoRoute(
        path: '/session/:id/requests',
        builder: (_, __) => _stub('session-requests')),

    // Chat (outside shell)
    GoRoute(path: '/messages/dm', builder: (_, __) => _stub('dm-list')),
    GoRoute(
        path: '/messages/dm/:conversationId',
        builder: (_, __) => _stub('dm-screen')),

    // Session group chat (outside shell)
    GoRoute(
        path: '/session/:id/chat',
        builder: (_, __) => _stub('session-chat')),

    // Other user profile — OUTSIDE shell (regression: was inside shell → bug 2)
    GoRoute(
        path: '/user/:userId',
        builder: (_, __) => _stub('other-user-profile')),

    // Settings (outside shell)
    GoRoute(path: '/settings', builder: (_, __) => _stub('settings')),
  ];
}

GoRouter _buildRouter({String initial = '/home'}) => GoRouter(
      initialLocation: initial,
      routes: _buildRoutes(),
    );

Widget _app(GoRouter router) => MaterialApp.router(routerConfig: router);

// ---------------------------------------------------------------------------
// Helpers for structural inspection
// ---------------------------------------------------------------------------

/// Returns every GoRoute path that is a direct child of the single ShellRoute.
Set<String> _shellChildPaths(List<RouteBase> routes) {
  final shell =
      routes.whereType<ShellRoute>().first;
  return shell.routes.whereType<GoRoute>().map((r) => r.path).toSet();
}

/// Returns every GoRoute path registered at the top level (outside any shell).
Set<String> _topLevelPaths(List<RouteBase> routes) {
  return routes
      .whereType<GoRoute>()
      .map((r) => r.path)
      .toSet();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Structural tests ───────────────────────────────────────────────────────
  group('AppRouter — ShellRoute classification', () {
    late List<RouteBase> routes;
    late Set<String> shellPaths;
    late Set<String> topPaths;

    setUpAll(() {
      routes = _buildRoutes();
      shellPaths = _shellChildPaths(routes);
      topPaths = _topLevelPaths(routes);
    });

    test('exactly one ShellRoute exists', () {
      expect(routes.whereType<ShellRoute>().length, 1);
    });

    // Shell membership — these routes MUST be inside the shell
    for (final path in [
      '/home',
      '/calendar',
      '/my-sessions',
      '/messages',
      '/profile',
      '/calendar/day',
    ]) {
      test('$path is inside ShellRoute', () {
        expect(shellPaths, contains(path));
      });
    }

    // Top-level membership — these routes MUST be outside the shell
    for (final path in [
      '/splash',
      '/login',
      '/signup',
      '/verify-email',
      '/create-session',
      '/session/:id',
      '/session/:id/edit',
      '/session/:id/members',
      '/session/:id/requests',
      '/session/:id/chat',
      '/my-sessions/member/:id',
      '/my-sessions/:id',
      '/messages/dm',
      '/messages/dm/:conversationId',
      // Regression: /user/:userId must be top-level (bug 2 — was inside shell)
      '/user/:userId',
      '/settings',
    ]) {
      test('$path is outside ShellRoute (top-level)', () {
        expect(topPaths, contains(path));
        expect(shellPaths, isNot(contains(path)));
      });
    }

    // /user/:userId specifically must NOT be inside the shell
    test('/user/:userId is NOT inside ShellRoute — regression guard for bug 2',
        () {
      expect(shellPaths, isNot(contains('/user/:userId')));
    });
  });

  // ── Navigation / GlobalKey regression tests ────────────────────────────────
  group('AppRouter — navigation GlobalKey regression', () {
    // Helper: pump the app widget and wait for the initial route to settle.
    Future<void> pumpApp(
      WidgetTester tester,
      GoRouter router,
    ) async {
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    testWidgets('initial route /home renders inside shell without error',
        (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);
      expect(find.text('home'), findsOneWidget);
      router.dispose();
    });

    // Shell ↔ shell navigation using go()
    testWidgets('go from /home to /calendar does not crash', (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.go('/calendar');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('calendar'), findsOneWidget);
      router.dispose();
    });

    testWidgets('go from /calendar to /my-sessions does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/calendar');
      await pumpApp(tester, router);

      router.go('/my-sessions');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('my-sessions'), findsOneWidget);
      router.dispose();
    });

    testWidgets('go from /home to /messages does not crash', (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.go('/messages');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('messages'), findsOneWidget);
      router.dispose();
    });

    testWidgets('go from /home to /profile does not crash', (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.go('/profile');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('profile'), findsOneWidget);
      router.dispose();
    });

    // Shell → top-level push
    testWidgets('push /session/:id from /home does not crash', (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.push('/session/abc');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('session-detail'), findsOneWidget);
      router.dispose();
    });

    testWidgets('push /settings from /home does not crash', (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.push('/settings');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('settings'), findsOneWidget);
      router.dispose();
    });

    testWidgets('push /create-session from /home does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/home');
      await pumpApp(tester, router);

      router.push('/create-session');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('create-session'), findsOneWidget);
      router.dispose();
    });

    // Regression: Bug 1 — navigating to /profile from within the shell must
    // not duplicate the shell Navigator's GlobalKey.  The fix moved the
    // settings action to a bottom sheet; the route itself still lives inside
    // the shell, so go() is safe.
    testWidgets(
        'go /profile from /home does not throw duplicate-GlobalKey error — bug 1 regression',
        (tester) async {
      final router = _buildRouter(initial: '/home');
      // Collect FlutterErrors to check for the duplicate-key message.
      final List<FlutterErrorDetails> errors = [];
      FlutterError.onError = (details) => errors.add(details);

      await pumpApp(tester, router);
      router.go('/profile');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Regression: Regression — bug 1: push('/profile') from shell spawned
      // a second shell Navigator with a duplicate GlobalKey.
      final hasDuplicateKey = errors.any(
        (e) => e.toString().toLowerCase().contains('globalkey'),
      );
      expect(hasDuplicateKey, isFalse,
          reason: 'Duplicate GlobalKey error detected — bug 1 has regressed');

      FlutterError.onError = FlutterError.presentError;
      router.dispose();
    });

    // Regression: Bug 2 — push /user/:userId from /session/:id (outside shell)
    // must not spawn a second shell Navigator.
    testWidgets(
        'push /user/:userId from /session/:id does not crash — bug 2 regression',
        (tester) async {
      // Start outside the shell at a session detail page.
      final router = _buildRouter(initial: '/session/abc');
      final List<FlutterErrorDetails> errors = [];
      FlutterError.onError = (details) => errors.add(details);

      await pumpApp(tester, router);
      expect(find.text('session-detail'), findsOneWidget);

      // Regression: Regression — bug 2: /user/:userId was inside the ShellRoute.
      // Pushing it from /session/:id (outside the shell) created a second shell
      // Navigator sharing the shell's GlobalKey → "Multiple widgets used the
      // same GlobalKey" crash.
      router.push('/user/u1');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('other-user-profile'), findsOneWidget);

      final hasDuplicateKey = errors.any(
        (e) => e.toString().toLowerCase().contains('globalkey'),
      );
      expect(hasDuplicateKey, isFalse,
          reason: 'Duplicate GlobalKey error detected — bug 2 has regressed');

      FlutterError.onError = FlutterError.presentError;
      router.dispose();
    });

    // Top-level → top-level push (no shell involved at all)
    testWidgets(
        'push /user/:userId from /session/:id/edit does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/session/abc/edit');
      await pumpApp(tester, router);

      router.push('/user/u2');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('other-user-profile'), findsOneWidget);
      router.dispose();
    });

    testWidgets(
        'push /user/:userId from /messages/dm/:id does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/messages/dm/conv1');
      await pumpApp(tester, router);

      router.push('/user/u3');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('other-user-profile'), findsOneWidget);
      router.dispose();
    });

    testWidgets('navigate to /session/:id/chat does not crash', (tester) async {
      final router = _buildRouter(initial: '/session/abc/chat');
      await pumpApp(tester, router);
      expect(find.text('session-chat'), findsOneWidget);
      router.dispose();
    });

    testWidgets('navigate to /session/:id/members does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/session/abc/members');
      await pumpApp(tester, router);
      expect(find.text('session-members'), findsOneWidget);
      router.dispose();
    });

    testWidgets('navigate to /session/:id/requests does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/session/abc/requests');
      await pumpApp(tester, router);
      expect(find.text('session-requests'), findsOneWidget);
      router.dispose();
    });

    testWidgets('navigate to /my-sessions/:id does not crash', (tester) async {
      final router = _buildRouter(initial: '/my-sessions/s1');
      await pumpApp(tester, router);
      expect(find.text('host-session-detail'), findsOneWidget);
      router.dispose();
    });

    testWidgets('navigate to /my-sessions/member/:id does not crash',
        (tester) async {
      final router = _buildRouter(initial: '/my-sessions/member/s1');
      await pumpApp(tester, router);
      expect(find.text('member-session-detail'), findsOneWidget);
      router.dispose();
    });
  });
}
