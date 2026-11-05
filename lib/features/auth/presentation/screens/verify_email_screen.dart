import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../auth_controller.dart';
import '../widgets/auth_widgets.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _resent = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final email = ref.watch(pendingVerificationEmailProvider);

    return AuthScaffold(
      title: 'Verify your email',
      showBackButton: false,
      subtitle: email == null
          ? 'Open the link we emailed you, then come back and log in.'
          : 'We sent a link to $email. Open it, then come back and log in.',
      children: [
        AuthErrorBanner(message: authErrorMessage(state)),
        if (_resent)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpace * 2),
            child: Text(
              'Sent again — give it a minute to arrive.',
              style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
            ),
          ),
        FilledButton(
          onPressed: () => context.go(Routes.login),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Back to log in'),
        ),
        const SizedBox(height: kSpace),
        TextButton(
          onPressed: email == null || state.isLoading
              ? null
              : () async {
                  final sent = await ref
                      .read(authControllerProvider.notifier)
                      .resendConfirmation();
                  if (sent && mounted) setState(() => _resent = true);
                },
          child: const Text('Resend the email'),
        ),
      ],
    );
  }
}
