import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/legal/privacy_content.dart';
import 'package:hati/features/legal/terms_content.dart';

import '../../support/app_harness.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillSignUp(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Display name'),
    'Bea',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email'),
    'bea@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'longenough1',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Confirm password'),
    'longenough1',
  );
}

void main() {
  group('Terms and Conditions (DECISIONS D-61)', () {
    testWidgets('can be read before signing in', (tester) async {
      final harness = await pumpApp(tester);

      await harness.go('/terms');

      expect(
        find.widgetWithText(AppBar, 'Terms and Conditions'),
        findsOneWidget,
      );
      expect(find.text('In short'), findsOneWidget);
    });

    testWidgets('can be read when signed in, from Profile', (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/profile');

      await _tapVisible(
        tester,
        find.widgetWithText(ListTile, 'Terms and Conditions'),
      );

      expect(
        find.widgetWithText(AppBar, 'Terms and Conditions'),
        findsOneWidget,
      );
    });

    testWidgets('carry the no-liability clause for payments and debts', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await harness.go('/terms');

      final clause = find.text(
        '5. No liability for transactions or unpaid settlements',
      );
      await tester.scrollUntilVisible(
        clause,
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(clause, findsOneWidget);
    });

    test('the liability limits keep what Philippine law will not waive', () {
      final text = [
        for (final s in kTermsSections)
          for (final b in s.blocks)
            if (b is LegalParagraph) b.text,
      ].join(' ');

      expect(text, contains('fraud, bad faith or gross negligence'));
      expect(text, contains('Republic Act No. 10173'));
      expect(text, contains('Republic Act No. 7394'));
    });

    testWidgets('email sign-up is refused until the Terms are ticked', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await harness.go('/sign-up');

      await _fillSignUp(tester);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );

      expect(
        find.text('Agree to the Terms and Conditions to continue'),
        findsOneWidget,
      );
      expect(harness.auth.calls, isNot(contains('signUp')));

      await _tapVisible(tester, find.byType(Checkbox));
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );

      expect(harness.auth.calls, contains('signUp'));
    });

    testWidgets('Welcome says at the bottom what continuing agrees to', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(
        find.textContaining(
          'By continuing, you agree to the Terms and Conditions and acknowledge '
          'the Privacy Notice.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('sign-up says Google sign-in agrees to the Terms', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      await harness.go('/sign-up');

      expect(
        find.textContaining(
          'By continuing with Google, you agree to the',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('the link in the notice opens the Terms', (tester) async {
      final harness = await pumpApp(tester);

      await tester.tapOnText(
        find.textRange.ofSubstring('Terms and Conditions'),
      );
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/terms');
    });
  });

  group('Privacy Notice (DECISIONS D-63)', () {
    testWidgets('can be read before signing in', (tester) async {
      final harness = await pumpApp(tester);

      await harness.go('/privacy');

      expect(find.widgetWithText(AppBar, 'Privacy Notice'), findsOneWidget);
    });

    testWidgets('is linked from the notice at the bottom of Welcome', (
      tester,
    ) async {
      final harness = await pumpApp(tester);

      await tester.tapOnText(find.textRange.ofSubstring('Privacy Notice'));
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/privacy');
    });

    testWidgets('is linked from Profile', (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/profile');

      await _tapVisible(
        tester,
        find.widgetWithText(ListTile, 'Privacy Notice'),
      );

      expect(harness.router.state.matchedLocation, '/privacy');
    });

    test('names the controller and the Data Privacy Act rights', () {
      final text = [
        for (final s in kPrivacySections)
          for (final b in s.blocks)
            switch (b) {
              LegalParagraph(:final text) => text,
              LegalBullets(:final items) => items.join(' '),
            },
      ].join(' ');

      expect(text, contains('Nex'));
      expect(text, contains('yakokakiiiii@gmail.com'));
      expect(text, contains('Republic Act No. 10173'));
      expect(text, contains('National Privacy Commission'));
      expect(text, contains('Delete account'));
    });

    test('the Terms carry no placeholders', () {
      final text = [
        for (final s in kTermsSections)
          for (final b in s.blocks)
            switch (b) {
              LegalParagraph(:final text) => text,
              LegalBullets(:final items) => items.join(' '),
            },
      ].join(' ');

      expect(text, isNot(contains('[')));
      expect(text, contains('Nex'));
    });
  });
}
