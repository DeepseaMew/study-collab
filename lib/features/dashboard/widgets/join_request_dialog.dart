import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/session.dart';

class JoinRequestDialog extends StatelessWidget {
  final Session session;
  const JoinRequestDialog({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Request to Join', style: tt.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send a join request to:',
            style: tt.bodyMedium?.copyWith(color: AppColors.hint),
          ),
          const SizedBox(height: 6),
          Text(
            '"${session.title}"',
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The host will review and approve or decline your request.',
                    style: tt.labelSmall?.copyWith(color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.hint)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(100, 40)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Send Request'),
        ),
      ],
    );
  }
}