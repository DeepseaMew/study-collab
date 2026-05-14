import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_user.dart';
import '../../../models/enums.dart';
import '../../../services/user_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../dashboard/widgets/session_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Local file shown immediately after picking, while the upload runs.
  /// Cleared once Firestore reflects the new URL.
  File? _localAvatar;
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar(AppUser user) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (xf == null) return;

    final file = File(xf.path);
    setState(() {
      _localAvatar = file;
      _uploadingAvatar = true;
    });

    try {
      final userService = ref.read(userServiceProvider);
      final url = await userService.uploadAvatar(userId: user.id, file: file);
      await userService.updateProfile(userId: user.id, profilePhotoUrl: url);
      if (mounted) setState(() => _localAvatar = null);
    } catch (e) {
      if (mounted) {
        setState(() => _localAvatar = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Avatar upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _openEditSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditProfileSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final tt = Theme.of(context).textTheme;

    return userAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('Not logged in')));
        }
        return _buildScaffold(context, tt, user);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, TextTheme tt, AppUser user) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // Avatar + name + email
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _uploadingAvatar
                      ? null
                      : () => _pickAndUploadAvatar(user),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.15,
                        ),
                        backgroundImage: _localAvatar != null
                            ? FileImage(_localAvatar!)
                            : (user.profilePhotoUrl != null &&
                                      user.profilePhotoUrl!.isNotEmpty
                                  ? NetworkImage(user.profilePhotoUrl!)
                                        as ImageProvider
                                  : null),
                        child:
                            (_localAvatar == null &&
                                (user.profilePhotoUrl == null ||
                                    user.profilePhotoUrl!.isEmpty))
                            ? Text(
                                user.username.isNotEmpty
                                    ? user.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              )
                            : null,
                      ),
                      if (_uploadingAvatar)
                        const Positioned.fill(
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.black38,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(user.username, style: tt.displayMedium),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    user.bio,
                    style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                if (user.faculty.isNotEmpty)
                  Text(
                    [
                      user.faculty,
                      'Year ${user.studentYear}',
                      user.academicLevel.displayName,
                    ].join(' · '),
                    style: tt.labelLarge?.copyWith(color: AppColors.hint),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Stats row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  label: 'Sessions',
                  value: user.sessionsCount.toString(),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                _StatItem(
                  label: 'Friends',
                  value: user.friendsCount.toString(),
                ),
                Container(width: 1, height: 36, color: AppColors.border),
                _RatingStatItem(sessionCount: user.sessionsCount),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Edit profile button
          OutlinedButton.icon(
            onPressed: () => _openEditSheet(user),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Profile'),
          ),
          const SizedBox(height: 28),
          // Session history — empty for now, real data wired later
          Text('Session History', style: tt.titleLarge),
          const SizedBox(height: 12),
          _SessionHistoryList(userId: user.id),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: tt.displayMedium?.copyWith(color: AppColors.accent)),
        const SizedBox(height: 2),
        Text(label, style: tt.bodyMedium?.copyWith(color: AppColors.hint)),
      ],
    );
  }
}

class _SessionHistoryList extends ConsumerWidget {
  final String userId;
  const _SessionHistoryList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(hostedSessionsProvider(userId));

    return sessionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Error: $e',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return const _EmptyHistory();
        }
        // Reuse the existing SessionCard from dashboard widgets so the UI
        // is consistent with what users see elsewhere.
        return Column(
          children: sessions
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SessionCard(session: s),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(
              Icons.history_outlined,
              size: 48,
              color: AppColors.disabled,
            ),
            const SizedBox(height: 12),
            Text(
              'No sessions yet',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingStatItem extends StatelessWidget {
  final int sessionCount;
  const _RatingStatItem({required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.thumb_up_rounded,
              color: Color(0xFF894DEF),
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              'N/A',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF894DEF),
              ),
            ),
          ],
        ),
        Text(
          'from $sessionCount sessions',
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.hint,
          ),
        ),
      ],
    );
  }
}

// ── Edit Profile Bottom Sheet ─────────────────────────────────────────────────

class EditProfileSheet extends ConsumerStatefulWidget {
  final AppUser user;
  const EditProfileSheet({super.key, required this.user});

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _facultyCtrl;
  late final TextEditingController _bioCtrl;
  late int _studentYear;
  late AcademicLevel _academicLevel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.username);
    _facultyCtrl = TextEditingController(text: widget.user.faculty);
    _bioCtrl = TextEditingController(text: widget.user.bio);
    _studentYear = widget.user.studentYear;
    _academicLevel = widget.user.academicLevel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _facultyCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  /// When academic level changes, clamp year to the new max.
  /// Undergraduate: 1–4, Postgraduate: 1–2.
  void _onLevelChanged(AcademicLevel? level) {
    if (level == null) return;
    setState(() {
      _academicLevel = level;
      final maxYear = AppUser.maxYearFor(level);
      if (_studentYear > maxYear) _studentYear = maxYear;
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(userServiceProvider)
          .updateProfile(
            userId: widget.user.id,
            username: _nameCtrl.text.trim(),
            faculty: _facultyCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            studentYear: _studentYear,
            academicLevel: _academicLevel,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final maxYear = AppUser.maxYearFor(_academicLevel);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Edit Profile', style: tt.displaySmall),
                const SizedBox(height: 20),
                _Field(label: 'Name', ctrl: _nameCtrl, hint: 'Your name'),
                const SizedBox(height: 14),
                _Field(
                  label: 'Faculty',
                  ctrl: _facultyCtrl,
                  hint: 'e.g. Engineering',
                ),
                const SizedBox(height: 14),
                Text(
                  'Academic Level',
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                // CHANGED: initialValue → value so the dropdown is controlled
                // and re-renders when _academicLevel changes via setState.
                DropdownButtonFormField<AcademicLevel>(
                  value: _academicLevel,
                  items: AcademicLevel.values
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(l.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: _onLevelChanged,
                ),
                const SizedBox(height: 14),
                Text(
                  'Year',
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                // CHANGED: initialValue → value so the year dropdown reflects
                // the clamped _studentYear after level changes.
                DropdownButtonFormField<int>(
                  value: _studentYear,
                  items: List.generate(maxYear, (i) => i + 1)
                      .map(
                        (y) =>
                            DropdownMenuItem(value: y, child: Text('Year $y')),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _studentYear = v);
                  },
                ),
                const SizedBox(height: 14),
                _Field(
                  label: 'Bio',
                  ctrl: _bioCtrl,
                  hint: 'Tell others about yourself...',
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final int maxLines;

  const _Field({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
