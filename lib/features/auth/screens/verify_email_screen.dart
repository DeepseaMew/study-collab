import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/auth_service.dart';
import '../providers/auth_providers.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _checking = false;
  bool _resending = false;

  Future<void> _checkVerified() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final verified =
          await ref.read(authServiceProvider).isEmailVerified();
      if (!mounted) return;
      if (verified) {
        // Force the auth providers to re-evaluate so the router redirect
        // sends us forward.
        ref.invalidate(authStateProvider);
        ref.invalidate(currentUserProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified! Welcome.'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Not verified yet. Click the link in your email, then try again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await ref.read(authServiceProvider).resendVerificationEmail();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification email sent. Check your inbox.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send email: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final email = ref.read(authServiceProvider).currentFirebaseUser?.email ??
        'your email';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.mark_email_unread_outlined,
                size: 80,
                color: AppColors.accent,
              ),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                style: tt.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to:',
                style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: tt.titleLarge?.copyWith(color: AppColors.accent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "Open your inbox, click the link, then come back and tap "
                "\"I've verified my email\".",
                style: tt.bodyMedium?.copyWith(color: AppColors.hint),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _checking ? null : _checkVerified,
                child: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("I've verified my email"),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _resending ? null : _resend,
                child: _resending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Resend email'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _signOut,
                child: const Text(
                  'Sign out',
                  style: TextStyle(color: AppColors.hint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}