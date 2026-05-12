import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const ComingSoonScreen({
    super.key,
    required this.title,
    this.subtitle = 'This feature is under construction.',
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: tt.headlineMedium,
            ),

            const SizedBox(height: 24),

            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(48),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Coming soon',
              style: tt.displaySmall,
            ),

            const SizedBox(height: 8),

            Text(
              subtitle,
              style: tt.bodyMedium?.copyWith(
                color: AppColors.hint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}