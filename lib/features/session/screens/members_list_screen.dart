import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/features/session/providers/session_providers.dart';
import 'package:study_collab/models/participant.dart';

/// Full members list for a session.
///
/// Route: /session/:id/members
/// This is a stub — full implementation is pending (Pass 3).
class MembersListScreen extends ConsumerWidget {
  final String id;
  const MembersListScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(sessionMembersProvider(id));

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
          'Members',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            e.toString(),
            style: const TextStyle(color: AppColors.hint),
          ),
        ),
        data: (members) => _MembersList(members: members),
      ),
    );
  }
}

class _MembersList extends StatelessWidget {
  final List<Participant> members;
  const _MembersList({required this.members});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(
        child: Text('No members yet.', style: TextStyle(color: AppColors.hint)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: members.length,
      separatorBuilder: (_, _) => const Divider(color: AppColors.border),
      itemBuilder: (_, i) {
        final m = members[i];
        final initial = m.username.isNotEmpty
            ? m.username[0].toUpperCase()
            : '?';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.secondary,
            backgroundImage:
                m.profilePhotoUrl != null && m.profilePhotoUrl!.isNotEmpty
                ? NetworkImage(m.profilePhotoUrl!)
                : null,
            child: m.profilePhotoUrl == null || m.profilePhotoUrl!.isEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          title: Text(
            m.username,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            m.isHost ? 'Host' : 'Member',
            style: const TextStyle(color: AppColors.hint, fontSize: 12),
          ),
        );
      },
    );
  }
}
