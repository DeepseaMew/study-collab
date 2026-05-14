import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/auth_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/screens/profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _allNotifications = true;
  bool _joinAlerts = true;
  bool _sessionReminders = true;
  bool _friendRequests = true;

  static const _toggleColor = Color(0xFF5186CD);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final authState = ref.watch(authStateProvider);
    final user = authState.maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── Profile ──────────────────────────────────────────────────────
          _SectionCard(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage:
                      (user?.profilePhotoUrl?.isNotEmpty ?? false)
                          ? NetworkImage(user!.profilePhotoUrl!)
                          : null,
                  child: (user == null ||
                          user.profilePhotoUrl == null ||
                          user.profilePhotoUrl!.isEmpty)
                      ? Text(
                          (user?.username.isNotEmpty ?? false)
                              ? user!.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  user?.username ?? 'Guest',
                  style: tt.titleLarge,
                ),
                subtitle: Text(
                  user?.email ?? '',
                  style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                ),
                trailing: TextButton(
                  onPressed: () {
                    final appUser =
                        ref.read(currentUserProvider).asData?.value;
                    if (appUser == null) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => EditProfileSheet(user: appUser),
                    );
                  },
                  child: const Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Notifications ────────────────────────────────────────────────
          // TODO: persist these toggles via shared_preferences or user settings doc.
          const _SectionLabel('Notifications'),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
              _ToggleTile(
                title: 'All Notifications',
                subtitle: 'Master toggle for all alerts',
                value: _allNotifications,
                color: _toggleColor,
                onChanged: (v) => setState(() {
                  _allNotifications = v;
                  if (!v) {
                    _joinAlerts = false;
                    _sessionReminders = false;
                    _friendRequests = false;
                  }
                }),
              ),
              const _Divider(),
              _ToggleTile(
                title: 'Join Request Alerts',
                subtitle: 'When someone requests to join your session',
                value: _joinAlerts && _allNotifications,
                color: _toggleColor,
                onChanged: _allNotifications
                    ? (v) => setState(() => _joinAlerts = v)
                    : null,
              ),
              const _Divider(),
              _ToggleTile(
                title: 'Session Reminders',
                subtitle: 'Reminders before sessions start',
                value: _sessionReminders && _allNotifications,
                color: _toggleColor,
                onChanged: _allNotifications
                    ? (v) => setState(() => _sessionReminders = v)
                    : null,
              ),
              const _Divider(),
              _ToggleTile(
                title: 'Friend Requests',
                subtitle: 'When someone sends you a friend request',
                value: _friendRequests && _allNotifications,
                color: _toggleColor,
                onChanged: _allNotifications
                    ? (v) => setState(() => _friendRequests = v)
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Account ──────────────────────────────────────────────────────
          const _SectionLabel('Account'),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.lock_outline, color: AppColors.text),
                title: Text(
                  'Change Password',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.hint,
                ),
                onTap: () => _showChangePassword(context),
              ),
              const _Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text(
                  'Sign Out',
                  style: tt.bodyMedium?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () => _showSignOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────

  void _showChangePassword(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
  }

  void _showSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) context.go(RouteNames.login);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not sign out. Please try again.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

// ── Shared layout helpers ───────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleLarge,
      );
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: AppColors.border,
      );
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool>? onChanged;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      title: Text(
        title,
        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: tt.labelSmall?.copyWith(color: AppColors.hint),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        thumbColor:
            WidgetStateProperty.resolveWith((s) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return color;
          return AppColors.border;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return color;
          return AppColors.border;
        }),
      ),
    );
  }
}

// ── Change password dialog (mock UI, no Firebase call yet) ──────────────
// TODO: wire to FirebaseAuth.currentUser?.updatePassword (requires recent login).

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    if (_newCtrl.text.isEmpty) return;
    if (_newCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password changed successfully!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PwField(
            ctrl: _currentCtrl,
            hint: 'Current password',
            obscure: _obscureCurrent,
            onToggle: () =>
                setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 12),
          _PwField(
            ctrl: _newCtrl,
            hint: 'New password',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 12),
          _PwField(
            ctrl: _confirmCtrl,
            hint: 'Confirm new password',
            obscure: _obscureConfirm,
            onToggle: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () => _save(context),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PwField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;

  const _PwField({
    required this.ctrl,
    required this.hint,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}