import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/notifications/data/notifications_repository.dart';
import 'package:hati/features/notifications/domain/notification_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_notifications_repository.dart';

final _members = [
  GroupMember(
    userId: 'bea',
    displayName: 'Bea',
    role: 'owner',
    joinedAt: DateTime.utc(2026, 1, 1),
  ),
  GroupMember(
    userId: 'carlo',
    displayName: 'Carlo',
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 2),
  ),
];

FakeGroupsRepository _groups() => FakeGroupsRepository(
      groups: const [
        GroupSummary(
          id: 'g1',
          name: 'Tagaytay Staycation',
          role: 'member',
          memberCount: 2,
        ),
      ],
      members: _members,
    );

AppNotification _notification({
  String id = 'n1',
  String type = 'bill_created',
  String title = 'Bea added Airbnb – 2 nights',
  String body = 'You owe ₱3,125.00.',
  Map<String, dynamic> data = const {'route': '/bills/bill-1'},
  DateTime? readAt,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      readAt: readAt,
      createdAt: DateTime.utc(2026, 9, 27, 10),
    );

void main() {
  group('AppNotification', () {
    test('knows whether it has been read', () {
      expect(_notification().isUnread, isTrue);
      expect(
        _notification(readAt: DateTime.utc(2026, 9, 28)).isUnread,
        isFalse,
      );
    });

    test('exposes a route only when there is one', () {
      expect(_notification().route, '/bills/bill-1');
      expect(_notification(data: const {}).route, isNull);
      expect(_notification(data: const {'route': ''}).route, isNull);
      expect(_notification(data: const {'route': 42}).route, isNull);
    });
  });

  group('NotificationFailure', () {
    test('maps every code nudge_share raises', () {
      const expected = {
        'HT050': NotificationFailureKind.shareNotFound,
        'HT051': NotificationFailureKind.notThePayer,
        'HT052': NotificationFailureKind.nothingToNudge,
        'HT053': NotificationFailureKind.nudgedTooRecently,
      };
      expected.forEach((code, kind) {
        expect(NotificationFailure.fromCode(code, 'x').kind, kind, reason: code);
      });
    });

    test('the rate limit explains itself', () {
      expect(
        NotificationFailure.fromCode('HT053', 'raw').displayMessage,
        contains('Give it a day'),
      );
    });
  });

  group('the bell (spec §10)', () {
    testWidgets('shows no badge when everything is read', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [_notification(readAt: DateTime.utc(2026, 9, 28))],
        ),
      );

      expect(find.byTooltip('Notifications'), findsOneWidget);
    });

    testWidgets('counts the unread ones, in the tooltip too', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [
            _notification(id: 'n1'),
            _notification(id: 'n2'),
            _notification(id: 'n3', readAt: DateTime.utc(2026, 9, 28)),
          ],
        ),
      );

      expect(find.byTooltip('2 unread notifications'), findsOneWidget);
    });

    testWidgets('uses the singular for one', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [_notification()],
        ),
      );

      expect(find.byTooltip('1 unread notification'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('says so when there is nothing', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
      );
      await harness.go('/notifications');

      expect(find.text('Nothing to catch up on'), findsOneWidget);
    });

    testWidgets('shows title and body', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [_notification()],
        ),
      );
      await harness.go('/notifications');

      expect(find.text('Bea added Airbnb – 2 nights'), findsOneWidget);
      expect(find.textContaining('You owe ₱3,125.00.'), findsOneWidget);
    });

    testWidgets('marks unread with a labelled dot, not colour alone',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [
            _notification(id: 'n1'),
            _notification(id: 'n2', readAt: DateTime.utc(2026, 9, 28)),
          ],
        ),
      );
      await harness.go('/notifications');

      // ListTile merges its descendants into one semantics node, so "Unread"
      // is announced as part of the tile rather than on its own.
      expect(find.bySemanticsLabel(RegExp('Unread')), findsOneWidget);
    });

    testWidgets('tapping marks it read and follows its route', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        notifications: FakeNotificationsRepository(
          notifications: [_notification()],
        ),
      );
      await harness.go('/notifications');

      await tester.tap(find.text('Bea added Airbnb – 2 nights'));
      await tester.pumpAndSettle();

      expect(harness.notifications.calls, contains('markRead'));
      expect(harness.notifications.lastArgs['id'], 'n1');
      // Asserting on what is on screen rather than the router's reported
      // location, which does not follow a push.
      expect(find.text('Who owes what'), findsOneWidget);
    });

    testWidgets('an already-read one is not marked again', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        notifications: FakeNotificationsRepository(
          notifications: [_notification(readAt: DateTime.utc(2026, 9, 28))],
        ),
      );
      await harness.go('/notifications');

      await tester.tap(find.text('Bea added Airbnb – 2 nights'));
      await tester.pumpAndSettle();

      expect(harness.notifications.calls, isNot(contains('markRead')));
      expect(find.text('Who owes what'), findsOneWidget);
    });

    testWidgets('Mark all read only appears when something is unread',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        notifications: FakeNotificationsRepository(
          notifications: [_notification()],
        ),
      );
      await harness.go('/notifications');

      expect(find.byTooltip('Mark all read'), findsOneWidget);
      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pumpAndSettle();

      expect(harness.notifications.calls, contains('markAllRead'));
      expect(find.byTooltip('Mark all read'), findsNothing);
    });
  });

  group('preferences (spec §5.1)', () {
    testWidgets('shows all five switches', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
      );
      await harness.go('/profile/notifications');

      expect(find.byType(SwitchListTile), findsNWidgets(5));
    });

    testWidgets('turning one off saves just that one', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
      );
      await harness.go('/profile/notifications');

      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();

      expect(harness.notifications.calls, contains('savePrefs'));
      final saved = harness.notifications.lastArgs['prefs']! as NotificationPrefs;
      expect(saved.comments, isFalse);
      expect(saved.newBill, isTrue, reason: 'the others are untouched');
      expect(saved.reminders, isTrue);
    });
  });

  group('nudge (spec §7.2)', () {
    testWidgets('the payer can nudge an unpaid share', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      await tester.tap(find.byTooltip('Options for Carlo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nudge'));
      await tester.pumpAndSettle();

      expect(harness.notifications.calls, contains('nudge'));
      expect(harness.notifications.lastArgs['billShareId'], 's2');
      expect(find.text('Nudged Carlo.'), findsOneWidget);
    });

    testWidgets('the rate limit is reported in plain words', (tester) async {
      final notifications = FakeNotificationsRepository()
        ..nudgeFailure = const NotificationFailure(
          NotificationFailureKind.nudgedTooRecently,
          'Already nudged in the last 24 hours',
        );

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        notifications: notifications,
      );
      await harness.go('/bills/bill-1');

      await tester.tap(find.byTooltip('Options for Carlo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nudge'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give it a day'), findsOneWidget);
    });

    testWidgets('a debtor is never offered it', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.byTooltip('Options for Bea'), findsNothing);
    });
  });
}
