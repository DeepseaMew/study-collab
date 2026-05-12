import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/errors/app_exceptions.dart';
import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/core/utils/date_formatter.dart';
import 'package:study_collab/features/auth/providers/auth_providers.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/models/join_request.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/services/participation_service.dart';

/// Full pending-requests list for a session. Host-only screen.
class RequestsScreen extends ConsumerWidget {
  final String sessionId;
  const RequestsScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionStreamProvider(sessionId));
    final requestsAsync = ref.watch(sessionRequestsProvider(sessionId));
    final me = ref.watch(currentUserProvider).asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
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
          'Requests',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(message: e.toString()),
        data: (session) {
          if (session == null) {
            return const _ErrorBody(message: 'Session not found.');
          }

          // Guard: only the host should see this screen.
          if (me == null || me.id != session.hostId) {
            return const _ErrorBody(
              message: 'Only the session host can view requests.',
            );
          }

          return requestsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorBody(message: e.toString()),
            data: (requests) => _RequestsList(
              session: session,
              requests: requests,
              callerUid: me.id,
            ),
          );
        },
      ),
    );
  }
}

// ── Requests list ─────────────────────────────────────────────────────────────

class _RequestsList extends StatelessWidget {
  final Session session;
  final List<JoinRequest> requests;
  final String callerUid;

  const _RequestsList({
    required this.session,
    required this.requests,
    required this.callerUid,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: AppColors.hint),
              SizedBox(height: 16),
              Text(
                'No pending requests',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'New join requests will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.hint, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _RequestCard(
        request: requests[i],
        session: session,
        callerUid: callerUid,
      ),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────────

class _RequestCard extends ConsumerStatefulWidget {
  final JoinRequest request;
  final Session session;
  final String callerUid;

  const _RequestCard({
    required this.request,
    required this.session,
    required this.callerUid,
  });

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _approvingLoading = false;
  bool _decliningLoading = false;

  Future<void> _approve() async {
    setState(() => _approvingLoading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .approveRequest(
            session: widget.session,
            callerUid: widget.callerUid,
            requestUserId: widget.request.userId,
            requestUsername: widget.request.username,
            requestUserPhotoUrl: widget.request.profilePhotoUrl,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not approve: ${_friendlyError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _approvingLoading = false);
    }
  }

  Future<void> _decline() async {
    // H1-followup: guard against signed-out state before calling service.
    if (widget.callerUid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be signed in')));
      return;
    }
    setState(() => _decliningLoading = true);
    try {
      await ref
          .read(participationServiceProvider)
          .declineRequest(
            sessionId: widget.session.id,
            callerUid: widget.callerUid,
            userId: widget.request.userId,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not decline: ${_friendlyError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _decliningLoading = false);
    }
  }

  String _friendlyError(Object e) =>
      e is AppException ? e.message : e.toString();

  @override
  Widget build(BuildContext context) {
    final initial = widget.request.username.isNotEmpty
        ? widget.request.username[0].toUpperCase()
        : '?';
    final isWorking = _approvingLoading || _decliningLoading;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── User info row ───────────────────────────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.secondary,
                backgroundImage:
                    widget.request.profilePhotoUrl != null &&
                        widget.request.profilePhotoUrl!.isNotEmpty
                    ? NetworkImage(widget.request.profilePhotoUrl!)
                    : null,
                child:
                    widget.request.profilePhotoUrl == null ||
                        widget.request.profilePhotoUrl!.isEmpty
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.username,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Requested ${DateFormatter.relative(widget.request.requestedAt)}',
                      style: const TextStyle(
                        color: AppColors.hint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Action buttons row ──────────────────────────────────────────────
          Row(
            children: [
              // Decline
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    foregroundColor: AppColors.error,
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isWorking ? null : _decline,
                  child: _decliningLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.error,
                          ),
                        )
                      : const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              // Approve
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isWorking ? null : _approve,
                  child: _approvingLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Approve',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Error body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
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
    );
  }
}
