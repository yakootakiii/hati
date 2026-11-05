import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/notifications/domain/notification_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_notifications_repository.dart';

// Invite by name (DECISIONS D-57).

final _invite = DirectInvite(
  id: 'inv1',
  groupId: 'g1',
  groupName: 'Baguio Trip',
  inviterName: 'Bea',
  memberCount: 3,
  createdAt: DateTime.utc(2026, 9, 28),
);

AppNotification _inviteNotification({String status = 'pending'}) =>
    AppNotification(
      id: 'n1',
      type: 'group_invite',
      title: 'Bea invited you to Baguio Trip',
      body: "Join to see and split the group's bills.",
      createdAt: DateTime.utc(2026, 9, 28, 10),
      data: {
        'invite_id': 'inv1',
        'group_id': 'g1',
        'group_name': 'Baguio Trip',
        'event_type': 'group_invite',
        'status': status,
      },
    );

FakeGroupsRepository _ownerOf({List<PersonResult> people = const []}) =>
    FakeGroupsRepository(
      groups: const [
        GroupSummary(
          id: 'g1',
          name: 'Baguio Trip',
          role: 'owner',
          memberCount: 1,
        ),
      ],
      people: people,
    );

void main() {
  group('Groups tab', () {
    testWidgets('shows an invite even before you are in any group', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: FakeGroupsRepository(directInvites: [_invite]),
      );
      await harness.go('/groups');

      expect(find.text('Bea invited you to Baguio Trip'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('No groups yet'), findsNothing);
    });

    testWidgets('Join accepts the invite', (tester) async {
      final groups = FakeGroupsRepository(directInvites: [_invite]);
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: groups,
      );
      await harness.go('/groups');

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(groups.calls, contains('respondToInvite'));
      expect(groups.lastArgs, {'inviteId': 'inv1', 'accept': true});
    });

    testWidgets('Decline declines it and the card goes away', (tester) async {
      final groups = FakeGroupsRepository(directInvites: [_invite]);
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: groups,
      );
      await harness.go('/groups');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(groups.lastArgs, {'inviteId': 'inv1', 'accept': false});
      expect(find.text('Bea invited you to Baguio Trip'), findsNothing);
    });

    testWidgets('the invite card fits at 200% text (D-53)', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: FakeGroupsRepository(directInvites: [_invite]),
        textScale: 2,
      );
      await harness.go('/groups');

      expect(tester.takeException(), isNull);
      expect(find.text('Join'), findsOneWidget);
    });
  });

  group('notification', () {
    testWidgets('a pending invite offers Join and Decline', (tester) async {
      final groups = FakeGroupsRepository(directInvites: [_invite]);
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: groups,
        notifications: FakeNotificationsRepository(
          notifications: [_inviteNotification()],
        ),
      );
      await harness.go('/notifications');

      expect(find.text('Bea invited you to Baguio Trip'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(groups.lastArgs, {'inviteId': 'inv1', 'accept': true});
    });

    testWidgets('an answered invite says so instead of offering buttons', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: FakeGroupsRepository(),
        notifications: FakeNotificationsRepository(
          notifications: [_inviteNotification(status: 'cancelled')],
        ),
      );
      await harness.go('/notifications');

      expect(find.textContaining('This invite was cancelled.'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });
  });

  group('invite sheet', () {
    Future<FakeGroupsRepository> openSheetAndSearch(
      WidgetTester tester,
      String query,
    ) async {
      final groups = _ownerOf(
        people: const [
          PersonResult(id: 'carlo', displayName: 'Carlo'),
          PersonResult(
            id: 'carla',
            displayName: 'Carla',
            status: 'pending',
            inviteId: 'inv9',
          ),
          PersonResult(id: 'dana', displayName: 'Dana', status: 'member'),
        ],
      );
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: groups,
      );
      await harness.go('/groups/g1');

      await tester.tap(find.byTooltip('Invite people'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      // Past the debounce.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      return groups;
    }

    testWidgets('does not search on a single character', (tester) async {
      final groups = await openSheetAndSearch(tester, 'c');

      expect(groups.calls, isNot(contains('searchPeople')));
    });

    testWidgets('lists people with what can be done for each', (tester) async {
      final groups = await openSheetAndSearch(tester, 'car');

      expect(groups.lastArgs, {'groupId': 'g1', 'query': 'car'});
      expect(find.widgetWithText(FilledButton, 'Invite'), findsOneWidget);
      expect(find.text('Invite sent'), findsOneWidget);
      expect(find.text('Already in the group'), findsOneWidget);
    });

    testWidgets('Invite sends one to that person', (tester) async {
      final groups = await openSheetAndSearch(tester, 'car');

      await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
      await tester.pumpAndSettle();

      expect(groups.argsByCall['invitePerson'], {
        'groupId': 'g1',
        'userId': 'carlo',
      });
      // And the results refresh, so Carlo now reads as invited.
      expect(groups.calls.where((c) => c == 'searchPeople'), hasLength(2));
    });

    testWidgets('Cancel withdraws a pending invite', (tester) async {
      final groups = await openSheetAndSearch(tester, 'car');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(groups.argsByCall['cancelDirectInvite'], {'inviteId': 'inv9'});
    });
  });
}
