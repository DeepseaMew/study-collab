import 'package:flutter/material.dart';

import '../widgets/session_form.dart';

/// Thin wrapper around [SessionForm] for the create-session flow.
///
/// Route: /create-session
/// Declared in lib/core/router/app_router.dart
class CreateSessionScreen extends StatelessWidget {
  const CreateSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SessionForm(isEditing: false);
  }
}
