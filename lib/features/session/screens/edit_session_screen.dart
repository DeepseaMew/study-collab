import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/services/session_service.dart';

import '../widgets/session_form.dart';

/// Edit-session screen.
///
/// Loads the session via [sessionStreamProvider], then renders [SessionForm]
/// pre-filled with the current data.
///
/// Route: /session/:id/edit
class EditSessionScreen extends ConsumerWidget {
  final String id;
  const EditSessionScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionStreamProvider(id));

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _ErrorScaffold(
        message: e is DataException ? e.message : e.toString(),
      ),
      data: (session) {
        if (session == null) {
          return const _ErrorScaffold(message: 'Session not found.');
        }

        // H3: Guard against non-hosts reaching this screen.
        final me = ref.watch(currentUserProvider).asData?.value;
        if (me == null || me.id != session.hostId) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.text,
                ),
                onPressed: () => context.pop(),
              ),
              title: const Text(
                'Edit Session',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            body: const Center(
              child: Text(
                'You are not authorized to edit this session.',
                style: TextStyle(color: AppColors.hint),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return SessionForm(
          isEditing: true,
          initialSession: session,
          bottomExtra: _DeleteSessionButton(sessionId: id),
        );
      },
    );
  }
}

// ── Delete button (sits below the form's bottom nav) ─────────────────────────

class _DeleteSessionButton extends StatelessWidget {
  final String sessionId;
  const _DeleteSessionButton({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.error,
          minimumSize: const Size(double.infinity, 44),
        ),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _DeleteDialog(sessionId: sessionId),
        ),
        child: const Text(
          'Delete Session',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// ── Delete confirmation dialog ─────────────────────────────────────────────────

class _DeleteDialog extends ConsumerStatefulWidget {
  final String sessionId;

  const _DeleteDialog({required this.sessionId});

  @override
  ConsumerState<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends ConsumerState<_DeleteDialog> {
  bool _deleting = false;

  Future<void> _delete() async {
    final me = ref.read(currentUserProvider).asData?.value;
    if (me == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _deleting = true);
    try {
      await ref
          .read(sessionServiceProvider)
          .deleteSession(sessionId: widget.sessionId, hostId: me.id);
      if (mounted) {
        Navigator.pop(context); // close dialog
        context.pop(); // back to detail or home
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is DataException ? e.message : e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Delete Session',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: const Text(
        'This will permanently delete the session and remove all members. '
        'This action cannot be undone.',
        style: TextStyle(color: AppColors.hint, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.hint)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            minimumSize: const Size(80, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _deleting ? null : _delete,
          child: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ── Error scaffold ─────────────────────────────────────────────────────────────

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.text,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Edit Session',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.hint),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.hint, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
