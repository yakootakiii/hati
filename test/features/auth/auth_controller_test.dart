import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/supabase/supabase_providers.dart';
import 'package:hati/features/auth/data/auth_repository.dart';
import 'package:hati/features/auth/domain/auth_failure.dart';
import 'package:hati/features/auth/presentation/auth_controller.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        isBackendConfiguredProvider.overrideWithValue(true),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await auth.dispose();
  });

  AuthController controller() => container.read(authControllerProvider.notifier);

  test('sign-up passes the display name through and remembers the email', () async {
    final ok = await controller().signUp(
      email: '  bea@example.com ',
      password: 'hunter22',
      displayName: 'Bea',
    );

    expect(ok, isTrue);
    expect(auth.calls, ['signUp']);
    expect(auth.lastDisplayName, 'Bea');
    expect(
      container.read(pendingVerificationEmailProvider),
      'bea@example.com',
      reason: 'the verify screen needs it for Resend',
    );
  });

  test('a failed sign-in surfaces the failure message and returns false', () async {
    auth.failWith = const AuthFailure(
      AuthFailureKind.invalidCredentials,
      "That email and password don't match an account.",
    );

    final ok = await controller().signIn(
      email: 'bea@example.com',
      password: 'wrong',
    );

    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(
      authErrorMessage(state),
      "That email and password don't match an account.",
    );
  });

  test('resend does nothing when no email is pending', () async {
    expect(await controller().resendConfirmation(), isFalse);
    expect(auth.calls, isEmpty);
  });

  test('resend uses the email captured at sign-up', () async {
    await controller().signUp(
      email: 'carlo@example.com',
      password: 'hunter22',
      displayName: 'Carlo',
    );

    expect(await controller().resendConfirmation(), isTrue);
    expect(auth.calls, ['signUp', 'resendConfirmation']);
    expect(auth.lastEmail, 'carlo@example.com');
  });

  test('signing out clears the pending email', () async {
    await controller().signUp(
      email: 'bea@example.com',
      password: 'hunter22',
      displayName: 'Bea',
    );
    await controller().signOut();

    expect(container.read(pendingVerificationEmailProvider), isNull);
  });
}
