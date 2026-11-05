import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/features/profile/data/account_repository.dart';

import '../../support/app_harness.dart';
import '../../support/fake_account_repository.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FilledButton _deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Delete my account'),
);

void main() {
  group('Delete account (DECISIONS D-64)', () {
    testWidgets('is reachable from Profile', (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/profile');

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, 'Delete account'),
      );

      expect(harness.router.state.matchedLocation, '/profile/delete-account');
      expect(
        find.text('This permanently deletes your Hati account.'),
        findsOneWidget,
      );
    });

    testWidgets('is refused while bills are open, and says which', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedIn,
        account: FakeAccountRepository(
          blockers: const [
            DeletionBlocker(
              groupName: 'Tagaytay Staycation',
              title: 'Airbnb – 2 nights',
              youOwe: false,
              amount: Money(625000),
            ),
          ],
        ),
      );
      await harness.go('/profile/delete-account');

      expect(find.text('Still open'), findsOneWidget);
      expect(find.text('Airbnb – 2 nights'), findsOneWidget);
      expect(find.text('Tagaytay Staycation · owed to you'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Delete my account'),
        findsNothing,
      );
    });

    testWidgets('needs DELETE typed before the button works', (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/profile/delete-account');

      expect(_deleteButton(tester).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'delete please',
      );
      await tester.pump();
      expect(_deleteButton(tester).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'DELETE',
      );
      await tester.pump();
      expect(_deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets('deleting signs out and lands on Welcome', (tester) async {
      final account = FakeAccountRepository();
      final harness = await pumpApp(
        tester,
        session: signedIn,
        account: account,
      );
      await harness.go('/profile/delete-account');

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'DELETE',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Delete my account'),
      );

      expect(account.calls, contains('deleteAccount'));
      expect(harness.router.state.matchedLocation, '/welcome');
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    testWidgets('a failure stays on the page and explains', (tester) async {
      final account = FakeAccountRepository()
        ..failWith = const AccountDeletionFailure(
          'Settle your open bills first, then try again.',
        );
      final harness = await pumpApp(
        tester,
        session: signedIn,
        account: account,
      );
      await harness.go('/profile/delete-account');

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'DELETE',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Delete my account'),
      );

      expect(
        find.text('Settle your open bills first, then try again.'),
        findsOneWidget,
      );
      expect(harness.router.state.matchedLocation, '/profile/delete-account');
    });
  });
}
