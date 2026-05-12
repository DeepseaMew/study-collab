import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/enums.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/search_bottom_sheet.dart';
import '../widgets/session_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Future<void> _onRefresh() async {
    // Mock refresh — TODO: trigger real session_service.watchPublicSessions
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() {});
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SearchBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // Auth — username + profile photo for the AppBar.
    final authState = ref.watch(authStateProvider);
    final firstName = authState.maybeWhen(
      data: (user) => user?.username.split(' ').first ?? 'Student',
      orElse: () => 'Student',
    );
    final avatarUrl = authState.maybeWhen(
      data: (user) => user?.profilePhotoUrl ?? '',
      orElse: () => '',
    );

    // Sessions list (mock for now).
    final asyncSessions = ref.watch(dashboardSessionsProvider);
final allSessions = asyncSessions.asData?.value ?? [];

// Debug: print errors and loading state
asyncSessions.whenOrNull(
  error: (e, _) => debugPrint('[dashboard] error: $e'),
);

if (asyncSessions.hasError) {
  return Center(child: Text('Dashboard error: ${asyncSessions.error}'));
}
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    
    // Discover feed = sessions the user has not joined / hosted yet.
    final discoverSessions = allSessions
        .where((s) => s.myStatus == JoinStatus.notJoined)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_greeting()}, $firstName 👋', style: tt.displaySmall),
            Text(
              'Find your next study session',
              style: tt.bodyMedium?.copyWith(color: AppColors.hint),
            ),
          ],
        ),
        actions: [
          // Profile avatar — left of notification bell
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.secondary,
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          // Notification bell with unread badge
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: badges.Badge(
              badgeContent: Text(
                '$unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              showBadge: unreadCount > 0,
              position: badges.BadgePosition.topEnd(top: -4, end: -4),
              badgeStyle: const badges.BadgeStyle(
                badgeColor: AppColors.accent,
                padding: EdgeInsets.all(4),
              ),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => context.push('/notifications'),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GestureDetector(
              onTap: _openSearch,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.hint, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Search sessions, #hashtags, @hosts...',
                      style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.accent,
              child: discoverSessions.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: discoverSessions.length,
                      itemBuilder: (context, index) =>
                          SessionCard(session: discoverSessions[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  size: 48,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text('All caught up!', style: tt.displaySmall),
              const SizedBox(height: 8),
              Text(
                "You've joined all available sessions.\nCreate one or check back later!",
                style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}