import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/surfaces.dart';
import '../widgets/google_sign_in_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: TermsNotice()),
      body: SafeArea(
        child: Padding(
          padding: kPagePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const BrandMark(size: 32),
                        const SizedBox(width: 10),
                        Text('Hati', style: theme.textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: kSpace * 4),
                    Text(
                      'Split the bill.\nKeep the barkada.',
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: kSpace * 1.5),
                    Text(
                      'Hati works out who owes what, shows them your GCash '
                      'or Maya QR, and keeps track until everyone is square.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: kSpace * 5),
                    const GoogleSignInButton(),
                    const SizedBox(height: kSpace * 1.5),
                    FilledButton(
                      onPressed: () => context.push(Routes.signUp),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Sign up with email'),
                    ),
                    const SizedBox(height: kSpace),
                    TextButton(
                      onPressed: () => context.push(Routes.login),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('I already have an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
