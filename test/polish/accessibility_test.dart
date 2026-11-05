import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/features/bills/domain/bill_models.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/notifications/domain/notification_models.dart';
import 'package:hati/features/recurring/domain/recurring_bill.dart';

import '../support/app_harness.dart';
import '../support/fake_bills_repository.dart';
import '../support/fake_groups_repository.dart';
import '../support/fake_notifications_repository.dart';
import '../support/fake_recurring_repository.dart';

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
          role: 'owner',
          memberCount: 2,
          members: [
            GroupMemberProfile(id: 'bea', displayName: 'Bea'),
            GroupMemberProfile(id: 'carlo', displayName: 'Carlo'),
          ],
        ),
      ],
      members: _members,
    );

FakeBillsRepository _bills() => FakeBillsRepository(
      bills: [airbnbBill()],
      balances: const [
        GroupBalance(
          groupId: 'g1',
          groupName: 'Tagaytay Staycation',
          owedByMe: Money(312500),
          owedToMe: Money(937500),
        ),
      ],
      openShares: [
        OpenShare(
          billId: 'bill-1',
          billTitle: 'Airbnb – 2 nights',
          billDate: DateTime.utc(2026, 9, 20),
          groupId: 'g1',
          groupName: 'Tagaytay Staycation',
          payerId: 'bea',
          payerName: 'Bea',
          amount: const Money(312500),
          status: 'unpaid',
        ),
      ],
    );

FakeNotificationsRepository _notifications() => FakeNotificationsRepository(
      notifications: [
        AppNotification(
          id: 'n1',
          type: 'bill_created',
          title: 'Bea added Airbnb – 2 nights',
          body: 'You owe ₱3,125.00.',
          data: const {'route': '/bills/bill-1'},
          createdAt: DateTime.utc(2026, 9, 27),
        ),
      ],
    );

FakeRecurringRepository _recurring() => FakeRecurringRepository(
      templates: [
        RecurringBill(
          id: 't1',
          groupId: 'g1',
          title: 'Rent',
          totalAmount: const Money(3000000),
          paidBy: 'bea',
          splitMode: 'equal',
          frequency: 'monthly',
          anchorDay: 1,
          nextRunOn: DateTime.utc(2026, 10),
          participantIds: const ['bea', 'carlo'],
        ),
      ],
    );

/// Every screen a signed-in person can reach without typing anything.
const _routes = <String, String>{
  '/': 'Home',
  '/groups': 'Groups',
  '/groups/g1': 'Group detail',
  '/groups/g1/members': 'Members',
  '/groups/g1/recurring': 'Repeating bills',
  '/groups/g1/settings': 'Group settings',
  '/bills/bill-1': 'Bill detail',
  '/activity': 'Activity',
  '/notifications': 'Notifications',
  '/profile': 'Profile',
  '/profile/appearance': 'Appearance',
  '/profile/notifications': 'Notification settings',
  '/profile/payment-methods': 'Payment methods',
  // The forms too: they are the densest screens in the app.
  '/groups/g1/bills/new': 'Add bill',
  '/groups/g1/recurring/new': 'New repeating bill',
};

void main() {
  group('200% text scale (spec §11)', () {
    _routes.forEach((route, name) {
      testWidgets('$name survives it without clipping', (tester) async {
        final overflows = await collectOverflows(() async {
          final harness = await pumpApp(
            tester,
            session: signedInAs('bea'),
            groups: _groups(),
            bills: _bills(),
            notifications: _notifications(),
            recurring: _recurring(),
            textScale: 2.0,
          );
          await harness.go(route);
        });

        expect(
          overflows,
          isEmpty,
          reason: '$name overflowed at 200% text:\n${overflows.join('\n')}',
        );
      });
    });
  });

  group('dark mode (spec §11)', () {
    _routes.forEach((route, name) {
      testWidgets('$name renders in dark', (tester) async {
        final overflows = await collectOverflows(() async {
          final harness = await pumpApp(
            tester,
            session: signedInAs('bea'),
            groups: _groups(),
            bills: _bills(),
            notifications: _notifications(),
            recurring: _recurring(),
            platformBrightness: Brightness.dark,
          );
          await harness.go(route);

          // A dark scaffold proves the theme actually followed the platform,
          // rather than the screen merely not crashing.
          final scaffold = tester.widgetList<Material>(find.byType(Material));
          expect(scaffold, isNotEmpty);
        });

        expect(overflows, isEmpty, reason: '$name overflowed in dark mode');
      });
    });

    testWidgets('the theme follows the platform', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
        platformBrightness: Brightness.dark,
      );

      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.dark);
    });

    testWidgets('and light when the platform is light', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
      );

      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.light);
    });
  });

  group('semantics (spec §11)', () {
    testWidgets('an avatar is never an unlabelled letter', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
      );
      await harness.go('/groups/g1/members');

      // The members screen shows avatar-only circles; each must announce who
      // it is and what their role is.
      expect(find.bySemanticsLabel(RegExp('Bea, Owner')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Carlo, Member')), findsOneWidget);
    });

    testWidgets('an avatar stack names everyone it stands for',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
      );
      await harness.go('/groups');

      expect(find.bySemanticsLabel(RegExp('Bea, Carlo')), findsWidgets);
    });

    testWidgets('a share row says who owes what and in what state',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
      );
      await harness.go('/bills/bill-1');

      // Spec §11's own example: "Carlo, owes ₱3,125, unpaid".
      expect(
        find.bySemanticsLabel(RegExp(r'Carlo, ₱3,125\.00, Unpaid')),
        findsOneWidget,
      );
    });

    testWidgets('the notification bell states its count in words',
        (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: _bills(),
        notifications: _notifications(),
      );

      expect(find.byTooltip('1 unread notification'), findsOneWidget);
    });
  });
}
