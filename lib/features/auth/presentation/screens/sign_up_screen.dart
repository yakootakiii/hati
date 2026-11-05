import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/auth_validators.dart';
import '../auth_controller.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/google_sign_in_button.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final created = await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _email.text,
          password: _password.text,
          displayName: _displayName.text,
        );

    if (created && mounted) {
      context.go(Routes.verifyEmail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'You only need a name and an email to start splitting.',
      footer: const TermsNotice(
        lead: 'By continuing with Google, you agree to the ',
      ),
      children: [
        AuthErrorBanner(message: authErrorMessage(state)),
        const GoogleSignInButton(),
        const AuthDivider(),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _displayName,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                maxLength: AuthValidators.maxDisplayNameLength,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  helperText: 'How your barkada will see you',
                ),
                validator: AuthValidators.displayName,
              ),
              const SizedBox(height: kSpace * 2),
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
                ),
                validator: AuthValidators.password,
              ),
              const SizedBox(height: kSpace * 2),
              TextFormField(
                controller: _confirmPassword,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (value) =>
                    AuthValidators.confirmPassword(value, _password.text),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: kSpace * 2),
              // Unticked by default: agreement has to be an act, not a
              // default (DECISIONS D-61).
              FormField<bool>(
                initialValue: false,
                validator: (value) => value == true
                    ? null
                    : 'Agree to the Terms and Conditions to continue',
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: field.value ?? false,
                          onChanged: field.didChange,
                          semanticLabel: 'I agree to the Terms and Conditions',
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                field.didChange(!(field.value ?? false)),
                            child: LegalLinksText(
                              lead: 'I agree to the ',
                              middle: ' and have read the ',
                              tail: '',
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          field.errorText!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: kSpace * 2),
              AuthSubmitButton(
                label: 'Create account',
                isBusy: state.isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: kSpace),
              TextButton(
                onPressed: () => context.go(Routes.login),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
