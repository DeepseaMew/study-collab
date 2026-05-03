import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../constants/route_names.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RouteNames.splash,
    debugLogDiagnostics: true,

    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      if (authState.isLoading) return null;

      final isAuthenticated = authState.value != null;
      final location = state.matchedLocation;

      final authRoutes = [
        RouteNames.splash,
        RouteNames.login,
        RouteNames.signup,
      ];
      final isOnAuthRoute = authRoutes.contains(location);

      if (!isAuthenticated && !isOnAuthRoute) return RouteNames.login;
      if (isAuthenticated && isOnAuthRoute) return RouteNames.home;

      return null;
    },

    refreshListenable: GoRouterRefreshStream(
      ref.read(authServiceProvider).authStateChanges(),
    ),

    routes: [
      // ── Auth ──────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.signup,
        builder: (context, state) => const SignupScreen(),
      ),

      // ── Home (placeholder — real UI replaces this) ────────────
      GoRoute(
        path: RouteNames.home,
        builder: (context, state) => const HomeScreen(),
      ),

      // ── Add routes below as screens are built ─────────────────
      // RouteNames.calendar    → CalendarScreen
      // RouteNames.messages    → ChatListScreen
      // RouteNames.mySessions  → MySessionsScreen
      // RouteNames.createSession → CreateSessionScreen
      // RouteNames.sessionDetails → SessionDetailsScreen
      // RouteNames.chatRoom    → ChatRoomScreen
      // RouteNames.profile     → ProfileScreen
      // RouteNames.notifications → NotificationsScreen
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}