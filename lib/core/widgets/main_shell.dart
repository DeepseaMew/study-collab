import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
// CHANGED: pending count for Sessions badge
import '../../features/auth/providers/auth_providers.dart';
import '../../features/dashboard/providers/dashboard_providers.dart';

const _kSelected = Color(0xFF5186CD);
const _kUnselected = AppColors.hint;

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/calendar')) return 1;
    if (loc.startsWith('/my-sessions')) return 2;
    if (loc.startsWith('/messages') && !loc.contains('/messages/')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = _selectedIndex(context);

    // TODO: wire to chat_service.watchUnreadCount() when chat_service exists.
    // Hardcoded to 0 during the session-feature work stream.
    const msgUnread = 0;

    // CHANGED: amber badge on Sessions when the user has pending join requests
    final me = ref.watch(currentUserProvider).asData?.value;
    final pendingCount = me != null
        ? ref
                .watch(pendingSessionsCountProvider(me.id))
                .asData
                ?.value ??
            0
        : 0;

    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-session'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: EdgeInsets.zero,
        color: AppColors.surface,
        notchMargin: 8,
        shape: const CircularNotchedRectangle(),
        elevation: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              active: sel == 0,
              onTap: () => context.go('/home'),
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded,
              label: 'Calendar',
              active: sel == 1,
              onTap: () => context.go('/calendar'),
            ),
            const SizedBox(width: 64), // FAB gap
            // CHANGED: amber badge when pending sessions exist
            _NavItem(
              icon: Icons.library_books_outlined,
              activeIcon: Icons.library_books_rounded,
              label: 'Sessions',
              active: sel == 2,
              badge: pendingCount > 0 ? pendingCount : null,
              badgeColor: const Color(0xFFD69E2E),
              onTap: () => context.go('/my-sessions'),
            ),
            _NavItem(
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'Messages',
              active: sel == 3,
              badge: msgUnread > 0 ? msgUnread : null,
              onTap: () => context.go('/messages'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final int? badge;
  // CHANGED: configurable badge colour (default red for messages, amber for sessions)
  final Color badgeColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
    this.badgeColor = AppColors.error,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      active ? activeIcon : icon,
      color: active ? _kSelected : _kUnselected,
      size: 22,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? _kSelected.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: badge != null
                  ? badges.Badge(
                      badgeContent: Text(
                        '$badge',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 8),
                      ),
                      // CHANGED: use instance badgeColor instead of hardcoded error red
                      badgeStyle: badges.BadgeStyle(
                        badgeColor: badgeColor,
                        padding: const EdgeInsets.all(3),
                      ),
                      position: badges.BadgePosition.topEnd(
                          top: -6, end: -6),
                      child: iconWidget,
                    )
                  : iconWidget,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.w400,
                color: active ? _kSelected : _kUnselected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}