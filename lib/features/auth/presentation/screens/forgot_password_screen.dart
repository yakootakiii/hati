import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/auth_validators.dart';
import '../auth_controller.dart';
import '../widgets/auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sent = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);

    if (sent && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    if (_sent) {
      return AuthScaffold(
        title: 'Check your inbox',
        subtitle:
            "We sent a reset link to ${_email.text.trim()}. Open it on this "
            'phone and you can set a new password.',
        children: [
          FilledButton(
            onPressed: () => context.pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Back to log in'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Reset your password',
      subtitle: "Tell us your email and we'll send a link to reset it.",
      children: [
        AuthErrorBanner(message: authErrorMessage(state)),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: AuthValidators.email,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: kSpace * 3),
              AuthSubmitButton(
                label: 'Send reset link',
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
