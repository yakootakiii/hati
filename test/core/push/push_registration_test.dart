import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_push.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/core/push/push_messaging.dart';
import 'package:hati/features/bills/domain/bill_models.dart';

void main() {
  group('push notifications (DECISIONS D-65)', () {
    testWidgets('a signed-in phone registers its token', (tester) async {
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        push: FakePushMessaging(),
        deviceTokens: tokens,
      );

      expect(tokens.calls, ['register:token-1:android']);
    });

    testWidgets('signing in later registers then', (tester) async {
      final tokens = FakeDeviceTokenRepository();
      final harness = await pumpApp(
        tester,
        push: FakePushMessaging(),
        deviceTokens: tokens,
      );
      expect(tokens.calls, isEmpty, reason: 'nobody to register for yet');

      harness.auth.signInAs('bea');
      await tester.pumpAndSettle();

      expect(tokens.calls, ['register:token-1:android']);
    });

    testWidgets('nothing registers if notifications are refused', (
      tester,
    ) async {
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        push: FakePushMessaging(permitted: false),
        deviceTokens: tokens,
      );

      expect(tokens.calls, isEmpty);
    });

    testWidgets('builds without Firebase simply skip push', (tester) async {
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        push: FakePushMessaging(available: false),
        deviceTokens: tokens,
      );

      expect(tokens.calls, isEmpty);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a refreshed token is registered again', (tester) async {
      final push = FakePushMessaging();
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        push: push,
        deviceTokens: tokens,
      );

      push.refresh('token-2');
      await tester.pumpAndSettle();

      expect(tokens.calls.last, 'register:token-2:android');
    });

    testWidgets('tapping a notification opens what it is about', (
      tester,
    ) async {
      final push = FakePushMessaging();
      final harness = await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        push: push,
      );

      push.tap('/bills/bill-1');
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/bills/bill-1');
    });

    testWidgets('signing out releases the phone first', (tester) async {
      final tokens = FakeDeviceTokenRepository();
      final harness = await pumpApp(
        tester,
        session: signedIn,
        push: FakePushMessaging(),
        deviceTokens: tokens,
      );
      await harness.go('/profile');

      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(tokens.calls.last, 'unregister:token-1');
      expect(harness.auth.calls.last, 'signOut');
    });
  });

  group('web push (DECISIONS D-72)', () {
    GroupBalance balance() => const GroupBalance(
      groupId: 'g1',
      groupName: 'Tagaytay Staycation',
      owedByMe: Money(312500),
      owedToMe: Money.zero,
    );

    testWidgets('waits for a tap, then registers the browser', (tester) async {
      final push = FakePushMessaging(web: true);
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(balances: [balance()]),
        push: push,
        deviceTokens: tokens,
      );

      expect(push.permissionRequests, 0, reason: 'never asks on its own');
      expect(tokens.calls, isEmpty);
      expect(find.text('Get notified when someone pays you'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Turn on'));
      await tester.pumpAndSettle();

      expect(push.permissionRequests, 1);
      expect(tokens.calls, ['register:token-1:web']);
      expect(find.text('Get notified when someone pays you'), findsNothing);
    });

    testWidgets('on an iPhone browser, explains the Home Screen step', (
      tester,
    ) async {
      await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(balances: [balance()]),
        push: FakePushMessaging(
          web: true,
          support: PushSupport.needsHomeScreen,
        ),
      );

      expect(find.textContaining('Add to Home Screen'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Turn on'), findsNothing);
    });

    testWidgets('a browser that already allowed it registers quietly', (
      tester,
    ) async {
      final tokens = FakeDeviceTokenRepository();
      await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(balances: [balance()]),
        push: FakePushMessaging(web: true, alreadyAllowed: true),
        deviceTokens: tokens,
      );

      expect(tokens.calls, ['register:token-1:web']);
      expect(find.text('Get notified when someone pays you'), findsNothing);
    });

    testWidgets('Not now hides it', (tester) async {
      await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(balances: [balance()]),
        push: FakePushMessaging(web: true),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Not now'));
      await tester.pumpAndSettle();

      expect(find.text('Get notified when someone pays you'), findsNothing);
    });

    testWidgets('the Android app never shows the card', (tester) async {
      await pumpApp(
        tester,
        session: signedIn,
        bills: FakeBillsRepository(balances: [balance()]),
        push: FakePushMessaging(),
      );

      expect(find.text('Get notified when someone pays you'), findsNothing);
    });
  });
}
