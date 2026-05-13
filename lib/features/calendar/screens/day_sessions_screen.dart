import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:study_collab/core/theme/app_theme.dart';
import 'package:study_collab/models/session.dart';
import 'package:study_collab/features/dashboard/widgets/session_card.dart';

class DaySessionsScreen extends StatelessWidget {
  final DateTime day;
  final List<Session> sessions;

  const DaySessionsScreen({
    super.key,
    required this.day,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // CHANGED: sort by startTime ascending inside build
    final sorted = [...sessions]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final n = sorted.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calendar',
              style: tt.labelSmall?.copyWith(color: AppColors.hint),
            ),
            Text(
              '${DateFormat('MMMM d').format(day)} — All Sessions',
              style: tt.titleLarge,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // CHANGED: session count label
          Text(
            '$n sessions · sorted by start time',
            style: tt.labelSmall?.copyWith(color: AppColors.hint),
          ),
          const SizedBox(height: 12),
          // CHANGED: full list of session cards
          ...sorted.map((s) => SessionCard(session: s)),
        ],
      ),
    );
  }
}

