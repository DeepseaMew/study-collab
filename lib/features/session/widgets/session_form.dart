// TODO(firebase-specialist): move Timestamp conversion into service layer so
// session_form.dart no longer needs to import cloud_firestore directly.
// The import is still needed for Timestamp.fromDate (startTime/endTime in the
// edit updates map) and FieldValue.delete() (M3 nullable-field clearing).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/models/enums.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/session_service.dart';

/// Multi-step form for creating or editing a session.
///
/// When [isEditing] is true, [initialSession] must be supplied.
/// Calls [SessionService.createSession] or [SessionService.editSession]
/// then pops the route on success.
class SessionForm extends ConsumerStatefulWidget {
  final bool isEditing;
  final Session? initialSession;

  /// Optional widget rendered below the bottom navigation bar.
  /// Used by [EditSessionScreen] to inject the Delete button.
  final Widget? bottomExtra;

  const SessionForm({
    super.key,
    this.isEditing = false,
    this.initialSession,
    this.bottomExtra,
  }) : assert(
         !isEditing || initialSession != null,
         'initialSession is required when isEditing is true',
       );

  @override
  ConsumerState<SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends ConsumerState<SessionForm>
    with SingleTickerProviderStateMixin {
  // ── Step index ──────────────────────────────────────────────────────────────
  int _step = 0;
  static const int _totalSteps = 3;

  // ── Step 1 – Basic info ──────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Subject _subject = Subject.computerScience;

  // ── Step 2 – Time & location ─────────────────────────────────────────────────
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 3));
  final _locationCtrl = TextEditingController();

  // ── Step 3 – Capacity, visibility & filters ──────────────────────────────────
  int _capacity = 5;
  String _visSegment = 'public'; // 'public' | 'private'
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  // Optional filters
  int? _studentYear;
  AcademicLevel? _academicLevel;

  // Hashtags
  final _hashtagCtrl = TextEditingController();
  final List<String> _hashtags = [];

  // ── Submit state ─────────────────────────────────────────────────────────────
  bool _submitting = false;

  // ── Computed ─────────────────────────────────────────────────────────────────
  SessionVisibility get _visibility => _visSegment == 'private'
      ? SessionVisibility.private
      : SessionVisibility.public;

  bool get _isEditing => widget.isEditing;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSession;
    if (s != null) {
      _titleCtrl.text = s.title;
      _descCtrl.text = s.description;
      _subject = s.subject;
      _startTime = s.startTime;
      _endTime = s.endTime;
      _locationCtrl.text = s.location;
      _capacity = s.capacity;
      _visSegment = s.visibility == SessionVisibility.private
          ? 'private'
          : 'public';
      _studentYear = s.studentYear;
      _academicLevel = s.academicLevel;
      _hashtags.addAll(s.hashtags);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _passwordCtrl.dispose();
    _hashtagCtrl.dispose();
    super.dispose();
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  bool _validate() {
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('Please enter a session title.');
      return false;
    }
    if (_locationCtrl.text.trim().isEmpty) {
      _showError('Please enter a location.');
      return false;
    }
    // L2: start time must be in the future (create path only).
    if (!_isEditing && _startTime.isBefore(DateTime.now())) {
      _showError('Session start time must be in the future.');
      return false;
    }
    if (_endTime.isBefore(_startTime) ||
        _endTime.isAtSameMomentAs(_startTime)) {
      _showError('End time must be after start time.');
      return false;
    }
    if (_capacity < 2) {
      _showError('Capacity must be at least 2.');
      return false;
    }
    if (_visibility == SessionVisibility.private &&
        _passwordCtrl.text.trim().isEmpty &&
        !_isEditing) {
      _showError('Please enter a password for the private session.');
      return false;
    }
    // L1: password minimum length (create path only).
    if (_visSegment == 'private' && !_isEditing) {
      if (_passwordCtrl.text.trim().length < 6) {
        _showError('Password must be at least 6 characters.');
        return false;
      }
    }
    return true;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_validate()) return;

    final me = ref.read(currentUserProvider).asData?.value;
    if (me == null) {
      _showError('You must be signed in.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final svc = ref.read(sessionServiceProvider);

      if (_isEditing) {
        final s = widget.initialSession!;
        final updates = <String, dynamic>{
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'subject': _subject.name,
          'location': _locationCtrl.text.trim(),
          'startTime': Timestamp.fromDate(_startTime),
          'endTime': Timestamp.fromDate(_endTime),
          'capacity': _capacity,
          'visibility': _visibility.name,
          'hashtags': _hashtags,
        };

        // M3: Explicitly delete nullable filter fields when cleared, so that
        // a previously-set value is removed rather than silently kept.
        updates['studentYear'] = _studentYear ?? FieldValue.delete();
        updates['academicLevel'] = _academicLevel != null
            ? _academicLevel!.name
            : FieldValue.delete();

        // If switching to private and a new password was entered, pass it
        // through a secondary service call is not available here — flag for
        // future: editSession does not support password re-hashing. For now
        // password changes on edit are not supported (by editSession design).

        await svc.editSession(
          sessionId: s.id,
          callerUid: me.id,
          updates: updates,
          updatedCardFields: const ['title', 'startTime', 'endTime', 'subject'],
        );
      } else {
        final now = DateTime.now();
        final newSession = Session(
          id: '',
          title: _titleCtrl.text.trim(),
          subject: _subject,
          description: _descCtrl.text.trim(),
          visibility: _visibility,
          hostId: me.id,
          hostName: me.username,
          hostPhotoUrl: me.profilePhotoUrl,
          startTime: _startTime,
          endTime: _endTime,
          location: _locationCtrl.text.trim(),
          capacity: _capacity,
          studentYear: _studentYear,
          academicLevel: _academicLevel,
          hashtags: _hashtags,
          createdAt: now,
          updatedAt: now,
        );
        await svc.createSession(
          session: newSession,
          plainTextPassword: _visibility == SessionVisibility.private
              ? _passwordCtrl.text.trim()
              : null,
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        _showError(e is DataException ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _nextStep() {
    if (_step < _totalSteps - 1) setState(() => _step++);
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
  // Warm up currentUserProvider so it's ready when submit is tapped.
  // Without this, the first submit returns AsyncLoading and shows
  // "You must be signed in" even for valid users.
    ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.text,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isEditing ? 'Edit Session' : 'Create Session',
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Step progress bar ───────────────────────────────────────────────
          _StepProgressBar(currentStep: _step, totalSteps: _totalSteps),
          // ── Page content ────────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _buildCurrentStep(),
            ),
          ),
          // ── Bottom navigation ───────────────────────────────────────────────
          _BottomNav(
            step: _step,
            totalSteps: _totalSteps,
            submitting: _submitting,
            canSubmit: ref.watch(currentUserProvider).asData?.value != null,
            onBack: _prevStep,
            onNext: _nextStep,
            onSubmit: _submit,
          ),
          if (widget.bottomExtra != null) widget.bottomExtra!,
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _Step1BasicInfo(
          key: const ValueKey('step0'),
          titleCtrl: _titleCtrl,
          descCtrl: _descCtrl,
          subject: _subject,
          onSubjectChanged: (s) => setState(() => _subject = s),
        );
      case 1:
        return _Step2TimeLocation(
          key: const ValueKey('step1'),
          startTime: _startTime,
          endTime: _endTime,
          locationCtrl: _locationCtrl,
          onStartTimeChanged: (dt) => setState(() => _startTime = dt),
          onEndTimeChanged: (dt) => setState(() => _endTime = dt),
        );
      case 2:
        return _Step3CapacityVisibility(
          key: const ValueKey('step2'),
          capacity: _capacity,
          visSegment: _visSegment,
          passwordCtrl: _passwordCtrl,
          obscurePassword: _obscurePassword,
          studentYear: _studentYear,
          academicLevel: _academicLevel,
          hashtags: _hashtags,
          hashtagCtrl: _hashtagCtrl,
          isEditing: _isEditing,
          onCapacityChanged: (v) => setState(() => _capacity = v),
          onVisSegmentChanged: (v) => setState(() => _visSegment = v),
          onObscureToggle: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onStudentYearChanged: (v) => setState(() => _studentYear = v),
          onAcademicLevelChanged: (v) => setState(() => _academicLevel = v),
          onAddHashtag: _addHashtag,
          onRemoveHashtag: (tag) => setState(() => _hashtags.remove(tag)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _addHashtag() {
    final tag = _hashtagCtrl.text.trim().replaceAll('#', '');
    if (tag.isNotEmpty && !_hashtags.contains(tag)) {
      setState(() {
        _hashtags.add(tag);
        _hashtagCtrl.clear();
      });
    }
  }
}

// ── Step progress bar ─────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final active = i <= currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Bottom navigation bar ─────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  const _BottomNav({
    required this.step,
    required this.totalSteps,
    required this.submitting,
    required this.canSubmit,    
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (step > 0)
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: submitting ? null : onBack,
                child: const Text('Back'),
              ),
            ),
          if (step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: submitting
    ? null
    : (isLast
        ? (canSubmit ? onSubmit : null)
        : onNext),
              child: submitting && isLast
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isLast ? 'Save Session' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1 — Basic info ───────────────────────────────────────────────────────

class _Step1BasicInfo extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final Subject subject;
  final ValueChanged<Subject> onSubjectChanged;

  const _Step1BasicInfo({
    super.key,
    required this.titleCtrl,
    required this.descCtrl,
    required this.subject,
    required this.onSubjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Session Title'),
          const SizedBox(height: 8),
          TextField(
            controller: titleCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: 'e.g. Data Structures Study Group',
              counterText: '',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'Description'),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'What will you cover in this session?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'Subject'),
          const SizedBox(height: 12),
          _SubjectGrid(selected: subject, onSelected: onSubjectChanged),
        ],
      ),
    );
  }
}

class _SubjectGrid extends StatelessWidget {
  final Subject selected;
  final ValueChanged<Subject> onSelected;

  const _SubjectGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: Subject.values.map((s) {
        final isSelected = s == selected;
        return GestureDetector(
          onTap: () => onSelected(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? s.color.withValues(alpha: 0.18)
                  : AppColors.secondary,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? s.color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              s.displayName,
              style: TextStyle(
                color: isSelected ? s.color : AppColors.hint,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Step 2 — Time & location ──────────────────────────────────────────────────

class _Step2TimeLocation extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final TextEditingController locationCtrl;
  final ValueChanged<DateTime> onStartTimeChanged;
  final ValueChanged<DateTime> onEndTimeChanged;

  const _Step2TimeLocation({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.locationCtrl,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
  });

  Future<void> _pickDateTime(
    BuildContext context,
    DateTime initial,
    ValueChanged<DateTime> onPicked,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Start Time'),
          const SizedBox(height: 8),
          _TimeTile(
            icon: Icons.calendar_today_outlined,
            label: _formatDateTime(startTime),
            onTap: () => _pickDateTime(context, startTime, onStartTimeChanged),
          ),
          const SizedBox(height: 16),
          _SectionLabel(label: 'End Time'),
          const SizedBox(height: 8),
          _TimeTile(
            icon: Icons.access_time_outlined,
            label: _formatDateTime(endTime),
            onTap: () => _pickDateTime(context, endTime, onEndTimeChanged),
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'Location'),
          const SizedBox(height: 8),
          TextField(
            controller: locationCtrl,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'e.g. LIB Building, Room 301',
              prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  $hour:$min';
  }
}

class _TimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TimeTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.hint),
          ],
        ),
      ),
    );
  }
}

// ── Step 3 — Capacity, visibility & filters ───────────────────────────────────

class _Step3CapacityVisibility extends StatelessWidget {
  final int capacity;
  final String visSegment;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final int? studentYear;
  final AcademicLevel? academicLevel;
  final List<String> hashtags;
  final TextEditingController hashtagCtrl;
  final bool isEditing;
  final ValueChanged<int> onCapacityChanged;
  final ValueChanged<String> onVisSegmentChanged;
  final VoidCallback onObscureToggle;
  final ValueChanged<int?> onStudentYearChanged;
  final ValueChanged<AcademicLevel?> onAcademicLevelChanged;
  final VoidCallback onAddHashtag;
  final ValueChanged<String> onRemoveHashtag;

  const _Step3CapacityVisibility({
    super.key,
    required this.capacity,
    required this.visSegment,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.studentYear,
    required this.academicLevel,
    required this.hashtags,
    required this.hashtagCtrl,
    required this.isEditing,
    required this.onCapacityChanged,
    required this.onVisSegmentChanged,
    required this.onObscureToggle,
    required this.onStudentYearChanged,
    required this.onAcademicLevelChanged,
    required this.onAddHashtag,
    required this.onRemoveHashtag,
  });

  @override
  Widget build(BuildContext context) {
    final isPrivate = visSegment == 'private';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Capacity stepper ──────────────────────────────────────────────
          _SectionLabel(label: 'Capacity'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.group_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 10),
                Text(
                  '$capacity members',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                _StepperBtn(
                  icon: Icons.remove,
                  onTap: capacity > 2
                      ? () => onCapacityChanged(capacity - 1)
                      : null,
                ),
                const SizedBox(width: 8),
                _StepperBtn(
                  icon: Icons.add,
                  onTap: capacity < 50
                      ? () => onCapacityChanged(capacity + 1)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Visibility segmented button ───────────────────────────────────
          _SectionLabel(label: 'Visibility'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              selectedBackgroundColor: AppColors.accent,
              selectedForegroundColor: Colors.white,
              foregroundColor: AppColors.hint,
              side: const BorderSide(color: AppColors.border),
            ),
            segments: const [
              ButtonSegment(
                value: 'public',
                label: Text('Public'),
                icon: Icon(Icons.public_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'private',
                label: Text('Private'),
                icon: Icon(Icons.lock_outline, size: 16),
              ),
            ],
            selected: {visSegment},
            onSelectionChanged: (s) => onVisSegmentChanged(s.first),
          ),
          const SizedBox(height: 8),

          // ── Visibility hint ───────────────────────────────────────────────
          if (!isPrivate)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Joining requires your approval',
                style: const TextStyle(color: AppColors.hint, fontSize: 12),
              ),
            ),

          // ── Password field (private only) ─────────────────────────────────
          if (isPrivate) ...[
            const SizedBox(height: 12),
            // M1: In edit mode the password is immutable — show a read-only
            // placeholder so the user knows a password exists without being
            // able to change it (password re-hashing is not supported by the
            // current editSession API).
            TextField(
              controller: passwordCtrl,
              readOnly: isEditing,
              obscureText: isEditing ? false : obscurePassword,
              decoration: InputDecoration(
                hintText: isEditing ? '••••••' : 'Session password',
                helperText: isEditing
                    ? 'Password cannot be changed after creation.'
                    : null,
                prefixIcon: const Icon(Icons.key_outlined, size: 18),
                suffixIcon: isEditing
                    ? null
                    : IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: AppColors.hint,
                        ),
                        onPressed: onObscureToggle,
                      ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Optional filters ──────────────────────────────────────────────
          _SectionLabel(label: 'Filters (optional)'),
          const SizedBox(height: 12),
          _AcademicLevelSelector(
            selected: academicLevel,
            onChanged: onAcademicLevelChanged,
          ),
          const SizedBox(height: 12),
          _StudentYearSelector(
            selected: studentYear,
            academicLevel: academicLevel,
            onChanged: onStudentYearChanged,
          ),
          const SizedBox(height: 20),

          // ── Hashtags ──────────────────────────────────────────────────────
          _SectionLabel(label: 'Hashtags (optional)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hashtagCtrl,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    hintText: 'e.g. algorithms',
                    prefixIcon: Icon(Icons.tag, size: 18),
                    counterText: '',
                  ),
                  onSubmitted: (_) => onAddHashtag(),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(56, 48),
                ),
                onPressed: onAddHashtag,
                child: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
          if (hashtags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: hashtags
                  .map(
                    (tag) => _HashtagChip(
                      tag: tag,
                      onRemove: () => onRemoveHashtag(tag),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AcademicLevelSelector extends StatelessWidget {
  final AcademicLevel? selected;
  final ValueChanged<AcademicLevel?> onChanged;

  const _AcademicLevelSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Level:',
          style: TextStyle(color: AppColors.hint, fontSize: 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Any',
                selected: selected == null,
                onTap: () => onChanged(null),
              ),
              ...AcademicLevel.values.map(
                (l) => _FilterChip(
                  label: l.displayName,
                  selected: selected == l,
                  onTap: () => onChanged(selected == l ? null : l),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentYearSelector extends StatelessWidget {
  final int? selected;
  final AcademicLevel? academicLevel;
  final ValueChanged<int?> onChanged;

  const _StudentYearSelector({
    required this.selected,
    required this.academicLevel,
    required this.onChanged,
  });

  // Matches AppUser.maxYearFor — undergrad 4, postgrad 2.
  int get _maxYear => academicLevel == AcademicLevel.postgraduate ? 2 : 4;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Year:',
          style: TextStyle(color: AppColors.hint, fontSize: 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Any',
                selected: selected == null,
                onTap: () => onChanged(null),
              ),
              ...List.generate(_maxYear, (i) {
                final year = i + 1;
                return _FilterChip(
                  label: 'Year $year',
                  selected: selected == year,
                  onTap: () => onChanged(selected == year ? null : year),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Small reusable widgets ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.secondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.hint,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _HashtagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;

  const _HashtagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.secondary : AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.accent : AppColors.hint,
        ),
      ),
    );
  }
}
