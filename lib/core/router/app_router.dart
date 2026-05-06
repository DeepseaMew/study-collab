
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';

// TODO: uncomment imports as screens are built
// import '../../features/dashboard/screens/dashboard_screen.dart';
// import '../../features/calendar/screens/calendar_screen.dart';
// import '../../features/my_sessions/screens/my_sessions_screen.dart';
// import '../../features/messaging/screens/messages_screen.dart';
// import '../../features/messaging/screens/dm_screen.dart';
// import '../../features/profile/screens/profile_screen.dart';
// import '../../features/profile/screens/other_user_profile_screen.dart';
// import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
// import '../../features/session/screens/create_session_screen.dart';
// import '../../features/session/screens/edit_session_screen.dart';
// import '../../features/session/screens/session_detail_screen.dart';
// import '../../features/session/screens/members_list_screen.dart';
// import '../../features/session/screens/chat_screen.dart';
// import '../../features/session/screens/notes_screen.dart';
// import '../../features/session/screens/requests_screen.dart';
// import '../widgets/main_shell.dart';

/// Riverpod provider for the app router.
///
/// Wrapping the router in a provider lets us add auth-aware redirects later
/// by reading the auth state inside the router (e.g. ref.watch(authStateProvider)).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      // ── Auth flow ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),

      // ── Home placeholder ─────────────────────────────────────────────────
      // Will be replaced by ShellRoute + DashboardScreen once dashboard is built.
      GoRoute(
        path: '/home',
        builder: (context, state) => const DashboardScreen(),
      ),
      
      // TODO: replace _HomePlaceholder with the real ShellRoute below
      // once main_shell.dart and inner screens are built and migrated to Riverpod.
      //
      // ShellRoute(
      //   builder: (c, s, child) => MainShell(child: child),
      //   routes: [
      //     GoRoute(path: '/home',        builder: (c, s) => const DashboardScreen()),
      //     GoRoute(path: '/calendar',    builder: (c, s) => const CalendarScreen()),
      //     GoRoute(path: '/my-sessions', builder: (c, s) => const MySessionsScreen()),
      //     GoRoute(path: '/messages',    builder: (c, s) => const MessagesScreen()),
      //     GoRoute(path: '/profile',     builder: (c, s) => const ProfileScreen()),
      //   ],
      // ),

      // TODO: session flows
      // GoRoute(path: '/create-session', builder: (c, s) => CreateSessionScreen(
      //   initialDate: s.extra is DateTime ? s.extra as DateTime : null,
      // )),
      // GoRoute(path: '/session/:id', builder: (c, s) =>
      //   SessionDetailScreen(id: s.pathParameters['id']!)),
      // GoRoute(path: '/session/:id/edit', builder: (c, s) =>
      //   EditSessionScreen(id: s.pathParameters['id']!)),
      // GoRoute(path: '/session/:id/members', builder: (c, s) =>
      //   MembersListScreen(id: s.pathParameters['id']!)),
      // GoRoute(path: '/session/:id/chat', builder: (c, s) =>
      //   ChatScreen(sessionId: s.pathParameters['id']!)),
      // GoRoute(path: '/session/:id/notes', builder: (c, s) =>
      //   NotesScreen(sessionId: s.pathParameters['id']!)),
      // GoRoute(path: '/session/:id/requests', builder: (c, s) =>
      //   RequestsScreen(sessionId: s.pathParameters['id']!)),

      // TODO: profile / messaging / notifications / settings
      // GoRoute(path: '/user/:id', builder: (c, s) =>
      //   OtherUserProfileScreen(userId: s.pathParameters['id']!)),
      // GoRoute(path: '/messages/:id', builder: (c, s) =>
      //   DmScreen(userId: s.pathParameters['id']!)),
      // GoRoute(path: '/notifications', builder: (c, s) => const NotificationsScreen()),
       GoRoute(path: '/settings',      builder: (c, s) => const SettingsScreen()),
    ],
  );
});

/// Temporary home screen until the real dashboard is migrated.
