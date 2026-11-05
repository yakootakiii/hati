import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/features/activity/domain/activity_event.dart';
import 'package:hati/features/activity/domain/comment.dart';
import 'package:hati/features/groups/domain/group_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_activity_repository.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_realtime_service.dart';

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

ActivityEvent _event({
  required String id,
  required String type,
  required DateTime at,
  String groupId = 'g1',
  String groupName = 'Tagaytay Staycation',
  String? actorId = 'bea',
  String? actorName = 'Bea',
  String? billId = 'bill-1',
  Map<String, dynamic> payload = const {'bill_title': 'Airbnb – 2 nights'},
}) =>
    ActivityEvent(
      id: id,
      groupId: groupId,
      groupName: groupName,
      type: type,
      createdAt: at,
      actorId: actorId,
      actorName: actorName,
      billId: billId,
      payload: payload,
    );

/// The comment thread lives at the bottom of Bill detail, past the end of the
/// ListView's build window, so a test has to scroll to it first.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('event copy (spec §5.3)', () {
    test('reads naturally for someone else and for you', () {
      final event = _event(
        id: 'e1',
        type: 'bill_created',
        at: DateTime.utc(2026, 9, 20),
        payload: const {'bill_title': 'Airbnb – 2 nights', 'amount': 1250000},
      );

      expect(
        event.describe(actorIsMe: false),
        'Bea added Airbnb – 2 nights · ₱12,500.00',
      );
      expect(
        event.describe(actorIsMe: true),
        'You added Airbnb – 2 nights · ₱12,500.00',
      );
    });

    test('covers every type in the spec without falling through', () {
      const types = [
        'group_created',
        'member_joined',
        'member_left',
        'member_removed',
        'bill_created',
        'bill_edited',
        'bill_voided',
        'payment_marked',
        'payment_confirmed',
        'payment_rejected',
        'bill_settled',
        'comment_added',
        'recurring_created',
        'recurring_generated',
      ];

      for (final type in types) {
        final event = _event(
          id: 't',
          type: type,
          at: DateTime.utc(2026),
        );
        expect(event.kind, isNot(ActivityType.unknown), reason: type);
        expect(
          event.describe(actorIsMe: false),
          isNot('Something happened'),
          reason: type,
        );
      }
    });

    test('an unrecognised type degrades rather than crashing', () {
      final event = _event(id: 'x', type: 'teleported', at: DateTime.utc(2026));
      expect(event.kind, ActivityType.unknown);
      expect(event.describe(actorIsMe: false), 'Something happened');
    });

    test('a rejection carries the reason the payer gave', () {
      final event = _event(
        id: 'e',
        type: 'payment_rejected',
        at: DateTime.utc(2026),
        payload: const {
          'bill_title': 'Airbnb',
          'reason': 'Nothing arrived in GCash',
        },
      );
      expect(
        event.describe(actorIsMe: false),
        contains('Nothing arrived in GCash'),
      );
    });

    test('a comment event reads from its excerpt, not the comment row', () {
      final event = _event(
        id: 'e',
        type: 'comment_added',
        at: DateTime.utc(2026),
        payload: const {'bill_title': 'Airbnb', 'excerpt': 'Booked it!'},
      );
      expect(event.describe(actorIsMe: false), contains('Booked it!'));
    });

    test('member events name the subject, not the actor', () {
      final event = _event(
        id: 'e',
        type: 'member_removed',
        at: DateTime.utc(2026),
        actorName: 'Bea',
        payload: const {'display_name': 'Dana'},
      );
      expect(event.describe(actorIsMe: false), 'Dana was removed by Bea');
    });

    test('an event with no bill has nowhere to navigate', () {
      final withBill = _event(id: 'a', type: 'bill_created', at: DateTime.utc(2026));
      final withoutBill = _event(
        id: 'b',
        type: 'member_joined',
        at: DateTime.utc(2026),
        billId: null,
      );

      expect(withBill.route, '/bills/bill-1');
      expect(withoutBill.route, isNull);
    });

    test('amounts render as pesos', () {
      final event = _event(
        id: 'e',
        type: 'payment_confirmed',
        at: DateTime.utc(2026),
        payload: const {'bill_title': 'Airbnb', 'amount': 312500},
      );
      expect(event.amount, const Money(312500));
      expect(event.describe(actorIsMe: false), contains('₱3,125.00'));
    });
  });

  group('Comment', () {
    test('a deleted comment keeps its place with a tombstone', () {
      final deleted = Comment(
        id: 'c1',
        billId: 'bill-1',
        authorId: 'carlo',
        body: 'oops',
        createdAt: DateTime.utc(2026),
        deletedAt: DateTime.utc(2026, 1, 2),
      );

      expect(deleted.isDeleted, isTrue);
      expect(deleted.displayBody, 'Comment deleted');
      expect(
        deleted.wasEdited,
        isFalse,
        reason: 'a deletion is not an edit',
      );
    });

    test('an edited comment says so', () {
      final edited = Comment(
        id: 'c1',
        billId: 'bill-1',
        authorId: 'carlo',
        body: 'fixed',
        createdAt: DateTime.utc(2026),
        editedAt: DateTime.utc(2026, 1, 2),
      );
      expect(edited.wasEdited, isTrue);
      expect(edited.displayBody, 'fixed');
    });
  });

  group('the feed screen (spec §10)', () {
    testWidgets('shows an empty state when there is nothing', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
      );
      await harness.go('/activity');

      expect(find.text('Nothing yet'), findsOneWidget);
    });

    testWidgets('lists events newest first, naming the group', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        activity: FakeActivityRepository(
          events: [
            _event(
              id: 'old',
              type: 'bill_created',
              at: DateTime.utc(2026, 9, 20),
            ),
            _event(
              id: 'new',
              type: 'bill_settled',
              at: DateTime.utc(2026, 9, 25),
            ),
          ],
        ),
      );
      await harness.go('/activity');

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      final settledAt = texts.indexWhere((t) => t.contains('fully settled'));
      final addedAt = texts.indexWhere((t) => t.contains('Bea added'));

      expect(settledAt, isNonNegative);
      expect(addedAt, isNonNegative);
      expect(
        settledAt,
        lessThan(addedAt),
        reason: 'the newer event should come first',
      );
      expect(find.textContaining('Tagaytay Staycation'), findsWidgets);
    });

    testWidgets('the group tab asks only for that group', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        activity: FakeActivityRepository(
          events: [
            _event(id: 'a', type: 'bill_created', at: DateTime.utc(2026, 9, 20)),
            _event(
              id: 'b',
              type: 'bill_created',
              at: DateTime.utc(2026, 9, 21),
              groupId: 'other',
              groupName: 'Office Lunch',
            ),
          ],
        ),
      );
      await harness.go('/groups/g1');
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(harness.activity.lastArgs['groupId'], 'g1');
    });
  });

  group('comments on a bill', () {
    testWidgets('an empty thread invites the first comment', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');
      await scrollTo(tester, find.text('Comments'));

      expect(find.text('Comments'), findsOneWidget);
      expect(find.textContaining('No comments yet'), findsOneWidget);
    });

    testWidgets('posting sends the body and clears the composer',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      final composer = find.widgetWithText(TextField, 'Add a comment');
      await scrollTo(tester, composer);
      await tester.ensureVisible(composer);
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'Booked it, thanks!');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(harness.activity.calls, contains('addComment'));
      expect(harness.activity.lastArgs['body'], 'Booked it, thanks!');
      expect(harness.activity.lastArgs['billId'], 'bill-1');
    });

    testWidgets('send is disabled until something is typed', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');
      await scrollTo(tester, find.byIcon(Icons.send));
      await tester.ensureVisible(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('whitespace alone is not a comment', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      final composer = find.widgetWithText(TextField, 'Add a comment');
      await scrollTo(tester, composer);
      await tester.ensureVisible(composer);
      await tester.pumpAndSettle();
      await tester.enterText(composer, '   ');
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('only your own comments offer edit and delete', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        activity: FakeActivityRepository(
          comments: [
            Comment(
              id: 'c1',
              billId: 'bill-1',
              authorId: 'carlo',
              authorName: 'Carlo',
              body: 'Mine',
              createdAt: DateTime.utc(2026, 9, 21),
            ),
            Comment(
              id: 'c2',
              billId: 'bill-1',
              authorId: 'bea',
              authorName: 'Bea',
              body: 'Theirs',
              createdAt: DateTime.utc(2026, 9, 22),
            ),
          ],
        ),
      );
      await harness.go('/bills/bill-1');
      await scrollTo(tester, find.text('Mine'));

      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('Theirs'), findsOneWidget);
      expect(
        find.byTooltip('Comment options'),
        findsOneWidget,
        reason: 'one menu, on the viewer\'s own comment',
      );
    });

    testWidgets('a deleted comment shows a tombstone with no menu',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        activity: FakeActivityRepository(
          comments: [
            Comment(
              id: 'c1',
              billId: 'bill-1',
              authorId: 'carlo',
              authorName: 'Carlo',
              body: 'oops',
              createdAt: DateTime.utc(2026, 9, 21),
              deletedAt: DateTime.utc(2026, 9, 22),
            ),
          ],
        ),
      );
      await harness.go('/bills/bill-1');
      await scrollTo(tester, find.text('Comment deleted'));

      expect(find.text('Comment deleted'), findsOneWidget);
      expect(find.text('oops'), findsNothing);
      expect(find.byTooltip('Comment options'), findsNothing);
    });
  });

  group('realtime, scoped to the open screen (spec §4.3)', () {
    testWidgets('Group detail subscribes while open and closes on leaving',
        (tester) async {
      final realtime = FakeRealtimeService();
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        realtime: realtime,
      );

      await harness.go('/groups/g1');
      expect(realtime.watching, contains('group:g1'));
      expect(realtime.isOpen('group:g1'), isTrue);

      await harness.go('/');
      expect(realtime.closed, contains('group:g1'));
      expect(realtime.isOpen('group:g1'), isFalse);
    });

    testWidgets('Bill detail subscribes to its own bill', (tester) async {
      final realtime = FakeRealtimeService();
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        realtime: realtime,
      );

      await harness.go('/bills/bill-1');
      expect(realtime.watching, contains('bill:bill-1'));

      await harness.go('/');
      expect(realtime.closed, contains('bill:bill-1'));
    });

    testWidgets('a change refetches the bill', (tester) async {
      final realtime = FakeRealtimeService();
      final bills = FakeBillsRepository(bills: [airbnbBill()]);
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: bills,
        realtime: realtime,
      );
      await harness.go('/bills/bill-1');

      final before = bills.calls.where((c) => c == 'bill').length;

      realtime.fire('bill:bill-1');
      await tester.pumpAndSettle();

      expect(
        bills.calls.where((c) => c == 'bill').length,
        greaterThan(before),
        reason: 'a live change should pull the bill again',
      );
    });
  });
}
