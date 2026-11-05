import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/auth_validators.dart';
import '../auth_controller.dart';
import '../widgets/auth_widgets.dart';

/// Where the password-reset email lands (DECISIONS D-60).
///
/// The link signs the user in for recovery; the router keeps them here until
/// a new password is saved, after which it lets them through to Home.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref
        .read(authControllerProvider.notifier)
        .updatePassword(_password.text);

    // On success the router moves on by itself; this just says why.
    if (saved) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Set a new password',
      subtitle: 'Choose a new password for your Hati account.',
      showBackButton: false,
      children: [
        AuthErrorBanner(message: authErrorMessage(state)),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                ),
                validator: AuthValidators.password,
              ),
              const SizedBox(height: kSpace * 2),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (value) =>
                    AuthValidators.confirmPassword(value, _password.text),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: kSpace * 3),
              AuthSubmitButton(
                label: 'Save password',
                isBusy: state.isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
