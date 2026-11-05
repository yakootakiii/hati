import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/auth_failure.dart';
import '../../domain/auth_validators.dart';
import '../auth_controller.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/google_sign_in_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    // On success the router's redirect takes over; on failure the banner shows.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final failure = state.error;

    // An unverified account is a dead end on this screen — send them to the
    // notice, where Resend lives.
    final needsVerification =
        failure is AuthFailure &&
        failure.kind == AuthFailureKind.emailNotConfirmed;

    return AuthScaffold(
      title: 'Welcome back',
      footer: const TermsNotice(),
      children: [
        AuthErrorBanner(message: authErrorMessage(state)),
        if (needsVerification)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpace * 2),
            child: FilledButton.tonal(
              onPressed: () {
                ref
                    .read(pendingVerificationEmailProvider.notifier)
                    .set(_email.text);
                context.go(Routes.verifyEmail);
              },
              child: const Text('Resend the verification email'),
            ),
          ),
        const GoogleSignInButton(),
        const AuthDivider(),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: AuthValidators.email,
              ),
              const SizedBox(height: kSpace * 2),
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                validator: AuthValidators.loginPassword,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: kSpace * 3),
              AuthSubmitButton(
                label: 'Log in',
                isBusy: state.isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: kSpace),
              TextButton(
                onPressed: () => context.push(Routes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
              TextButton(
                onPressed: () => context.go(Routes.signUp),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
