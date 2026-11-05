import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/auth/domain/auth_failure.dart';
import 'package:hati/features/auth/domain/auth_snapshot.dart';

import '../../support/app_harness.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Continue with Google (DECISIONS D-60)', () {
    testWidgets('is offered on Welcome and opens Google', (tester) async {
      final harness = await pumpApp(tester);

      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Continue with Google'),
      );

      expect(harness.auth.calls, contains('signInWithGoogle'));
    });

    testWidgets('is offered on Log in and Sign up too', (tester) async {
      final harness = await pumpApp(tester);

      await harness.go('/login');
      expect(
        find.widgetWithText(OutlinedButton, 'Continue with Google'),
        findsOneWidget,
      );

      await harness.go('/sign-up');
      expect(
        find.widgetWithText(OutlinedButton, 'Continue with Google'),
        findsOneWidget,
      );
    });

    testWidgets('a failure to open Google shows inline', (tester) async {
      final harness = await pumpApp(tester);
      await harness.go('/login');
      harness.auth.failWith = const AuthFailure(
        AuthFailureKind.network,
        "Can't reach Hati right now.",
      );

      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Continue with Google'),
      );

      expect(find.text("Can't reach Hati right now."), findsOneWidget);
    });

    testWidgets('the session coming back lands on Home', (tester) async {
      final harness = await pumpApp(tester);

      harness.auth.signInAs('bea');
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/');
    });
  });

  group('password reset (DECISIONS D-60)', () {
    testWidgets('a reset link holds the user on Set a new password',
        (tester) async {
      final harness = await pumpApp(tester);

      harness.auth.emit(const AuthSnapshot(
        userId: 'bea',
        emailConfirmed: true,
        recoveringPassword: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Set a new password'), findsOneWidget);

      // Nowhere else is reachable until the password is saved.
      await harness.go('/groups');
      expect(find.text('Set a new password'), findsOneWidget);
    });

    testWidgets('saving the new password lets them through to Home',
        (tester) async {
      final harness = await pumpApp(tester);
      harness.auth.emit(const AuthSnapshot(
        userId: 'bea',
        emailConfirmed: true,
        recoveringPassword: true,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'longenough1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'longenough1',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save password'),
      );

      expect(harness.auth.calls, contains('updatePassword'));
      expect(harness.auth.lastPassword, 'longenough1');
      expect(harness.router.state.matchedLocation, '/');
    });

    testWidgets('mismatched passwords are caught before sending',
        (tester) async {
      final harness = await pumpApp(tester);
      harness.auth.emit(const AuthSnapshot(
        userId: 'bea',
        emailConfirmed: true,
        recoveringPassword: true,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'longenough1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'different22',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save password'),
      );

      expect(find.text("Those don't match"), findsOneWidget);
      expect(harness.auth.calls, isNot(contains('updatePassword')));
    });

    testWidgets('the reset screen is not reachable without a reset link',
        (tester) async {
      final harness = await pumpApp(tester, session: signedIn);

      await harness.go('/reset-password');

      expect(find.text('Set a new password'), findsNothing);
      expect(harness.router.state.matchedLocation, '/');
    });
  });
}
