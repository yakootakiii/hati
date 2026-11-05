import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_push.dart';

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

    testWidgets('nothing registers if notifications are refused',
        (tester) async {
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

    testWidgets('tapping a notification opens what it is about',
        (tester) async {
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
}
