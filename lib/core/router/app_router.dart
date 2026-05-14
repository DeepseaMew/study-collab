import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:study_collab/models/session.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../services/auth_service.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/other_user_profile_screen.dart';
import '../../features/my_sessions/screens/my_sessions_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/calendar/screens/day_sessions_screen.dart';
import '../../features/session/screens/create_session_screen.dart';
import '../../features/session/screens/edit_session_screen.dart';
import '../../features/session/screens/session_detail_screen.dart';
import '../../features/session/screens/members_list_screen.dart';
import '../../features/session/screens/requests_screen.dart';
import '../../features/my_sessions/screens/host_session_detail_screen.dart';
import '../../features/my_sessions/screens/member_session_detail_screen.dart';
import '../../features/chat/screens/messages_screen.dart';
import '../../features/chat/screens/dm_list_screen.dart';
import '../../features/chat/screens/dm_screen.dart';
import '../../features/chat/screens/session_chat_screen.dart';
import '../widgets/main_shell.dart';

/// Riverpod provider for the app router.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthChangeNotifier(ref),
    redirect: (context, state) {
      final firebaseUser = ref.read(authServiceProvider).currentFirebaseUser;
      final loc = state.matchedLocation;

      final isAuthRoute =
          loc == '/splash' || loc == '/login' || loc == '/signup';

      if (firebaseUser == null) {
        return isAuthRoute ? null : '/login';
      }

      if (!firebaseUser.emailVerified) {
        if (loc == '/verify-email' || loc == '/splash') return null;
        return '/verify-email';
      }

      if (isAuthRoute || loc == '/verify-email') return '/home';

      return null;
    },
    // The main routes array for the entire app
    routes: [
      // ── Auth flow ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
      ),

      // ── Main Navigation Shell (Bottom Bar) ─────────────────────────────────
      ShellRoute(
        builder: (c, s, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (c, s) => const DashboardScreen()),
          GoRoute(path: '/calendar', builder: (c, s) => const CalendarScreen()),
          GoRoute(
            path: '/my-sessions',
            builder: (c, s) => const MySessionsScreen(),
          ),
          GoRoute(path: '/messages', builder: (c, s) => const MessagesScreen()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          // CHANGED: day-drill-down route — stays inside ShellRoute so bottom nav shows
          GoRoute(
            path: '/calendar/day',
            builder: (c, s) {
              final args = s.extra! as (DateTime, List<Session>);
              return DaySessionsScreen(day: args.$1, sessions: args.$2);
            },
          ),
        ],
      ),

      // ── My-sessions detail screens (No bottom bar) ────────────────────────
      // CHANGED: moved out of ShellRoute so their keys never collide with
      // /my-sessions list route.  These screens have their own AppBar + back
      // button and do not need the shell's bottom navigation bar.
      GoRoute(
        path: '/my-sessions/member/:id',
        builder: (c, s) =>
            MemberSessionDetailScreen(sessionId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/my-sessions/:id',
        builder: (c, s) =>
            HostSessionDetailScreen(sessionId: s.pathParameters['id']!),
      ),

      // ── Session flows (No bottom bar) ──────────────────────────────────────
      GoRoute(
        path: '/create-session',
        builder: (c, s) => const CreateSessionScreen(),
      ),
      GoRoute(
        path: '/session/:id',
        builder: (c, s) =>
            SessionDetailScreen(sessionId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/session/:id/edit',
        builder: (c, s) => EditSessionScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/session/:id/members',
        builder: (c, s) => MembersListScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/session/:id/requests',
        builder: (c, s) => RequestsScreen(sessionId: s.pathParameters['id']!),
      ),

      // ── Chat: DM list & DM conversation (no bottom nav) ───────────────────
      GoRoute(path: '/messages/dm', builder: (c, s) => const DmListScreen()),
      GoRoute(
        path: '/messages/dm/:conversationId',
        builder: (c, s) =>
            DmScreen(conversationId: s.pathParameters['conversationId']!),
      ),

      // ── Chat: Session group chat (no bottom nav) ───────────────────────────
      GoRoute(
        path: '/session/:id/chat',
        builder: (c, s) =>
            SessionChatScreen(sessionId: s.pathParameters['id']!),
      ),

      // ── Other user profile (no bottom nav — pushed from session/chat/etc.) ──
      GoRoute(
        path: '/user/:userId',
        builder: (c, s) =>
            OtherUserProfileScreen(userId: s.pathParameters['userId']!),
      ),

      // ── Other ──────────────────────────────────────────────────────────────
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
    ],
  );
});

/// Bridges Riverpod auth state changes into GoRouter
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}
