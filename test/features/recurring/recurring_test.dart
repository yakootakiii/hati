import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/core/split/split.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/recurring/data/recurring_repository.dart';
import 'package:hati/features/recurring/domain/recurring_bill.dart';

import '../../support/app_harness.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_recurring_repository.dart';

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
          name: 'Kasama sa Bahay',
          role: 'owner',
          memberCount: 2,
        ),
      ],
      members: _members,
    );

RecurringBill _template({
  String id = 't1',
  String title = 'Rent',
  String frequency = 'monthly',
  int interval = 1,
  int? anchorDay = 1,
  bool paused = false,
  DateTime? nextRunOn,
}) =>
    RecurringBill(
      id: id,
      groupId: 'g1',
      title: title,
      totalAmount: const Money(3000000),
      paidBy: 'bea',
      splitMode: 'equal',
      frequency: frequency,
      interval: interval,
      anchorDay: anchorDay,
      nextRunOn: nextRunOn ?? DateTime.utc(2026, 10, 1),
      paused: paused,
      participantIds: const ['bea', 'carlo'],
    );

/// The form is taller than the 800x600 test surface, and a ListView does not
/// build what is scrolled out of view.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  try {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  } on Object {
    // Let the following expect report what is actually missing, rather than
    // failing here with an opaque "Bad state: No element".
  }
}

Future<void> fillForm(
  WidgetTester tester, {
  required String title,
  required String amount,
}) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'What is it for?'),
    title,
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount each time'),
    amount,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('schedule copy', () {
    test('reads naturally for each cadence', () {
      expect(_template().scheduleLabel, 'Monthly on the 1st');
      expect(
        _template(anchorDay: 2).scheduleLabel,
        'Monthly on the 2nd',
      );
      expect(
        _template(anchorDay: 3).scheduleLabel,
        'Monthly on the 3rd',
      );
      expect(
        _template(anchorDay: 21).scheduleLabel,
        'Monthly on the 21st',
      );
      expect(
        _template(frequency: 'weekly', anchorDay: null).scheduleLabel,
        'Weekly',
      );
      expect(
        _template(frequency: 'weekly', interval: 2, anchorDay: null)
            .scheduleLabel,
        'Every 2 weeks',
      );
      expect(
        _template(frequency: 'yearly', anchorDay: null).scheduleLabel,
        'Yearly',
      );
    });

    test('the teens keep their th', () {
      for (final day in [11, 12, 13]) {
        expect(
          _template(anchorDay: day).scheduleLabel,
          'Monthly on the ${day}th',
        );
      }
    });

    test('a template is never itemized (spec §5.1)', () {
      expect(_template().mode, isNot(SplitMode.itemized));
    });
  });

  group('RecurringFailure', () {
    test('keeps the split engine range apart from its own', () {
      expect(
        RecurringFailure.fromCode('HT024', 'percent_sum_mismatch').kind,
        RecurringFailureKind.splitInvalid,
      );
      expect(
        RecurringFailure.fromCode('HT062', 'bad cadence').kind,
        RecurringFailureKind.invalidRecurrence,
      );
      expect(
        RecurringFailure.fromCode('HT061', 'nope').kind,
        RecurringFailureKind.notAllowed,
      );
      expect(
        RecurringFailure.fromCode('HT060', 'gone').kind,
        RecurringFailureKind.notFound,
      );
    });

    test('a broken split says so in plain words', () {
      expect(
        RecurringFailure.fromCode('HT024', 'raw').displayMessage,
        contains("doesn't add up"),
      );
    });
  });

  group('the list (spec §10)', () {
    testWidgets('offers one clear action when empty', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring');

      expect(find.text('Nothing repeating yet'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'New repeating bill'),
        findsOneWidget,
      );
    });

    testWidgets('shows the schedule and next run', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: FakeRecurringRepository(templates: [_template()]),
      );
      await harness.go('/groups/g1/recurring');

      expect(find.text('Rent'), findsOneWidget);
      expect(find.textContaining('Monthly on the 1st'), findsOneWidget);
      expect(find.textContaining('Next on'), findsOneWidget);
      expect(find.text('₱30,000.00'), findsOneWidget);
    });

    testWidgets('a paused template says so in words, not just styling',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: FakeRecurringRepository(
          templates: [_template(paused: true)],
        ),
      );
      await harness.go('/groups/g1/recurring');

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
    });

    testWidgets('pausing sends the flag', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: FakeRecurringRepository(templates: [_template()]),
      );
      await harness.go('/groups/g1/recurring');

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(harness.recurring.calls, contains('setPaused'));
      expect(harness.recurring.lastArgs['templateId'], 't1');
      expect(harness.recurring.lastArgs['paused'], isTrue);
    });

    testWidgets('deleting asks first and says the bills survive',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: FakeRecurringRepository(templates: [_template()]),
      );
      await harness.go('/groups/g1/recurring');

      await tester.tap(find.byTooltip('Delete Rent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('bills it already made stay'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(harness.recurring.calls, contains('remove'));
      expect(harness.recurring.lastArgs['templateId'], 't1');
    });

    testWidgets('cancelling the delete does nothing', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: FakeRecurringRepository(templates: [_template()]),
      );
      await harness.go('/groups/g1/recurring');

      await tester.tap(find.byTooltip('Delete Rent'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(harness.recurring.calls, isNot(contains('remove')));
    });
  });

  group('the form', () {
    testWidgets('offers no Items mode — a template cannot be itemized',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring/new');

      await scrollTo(tester, find.text('Equal'));

      expect(find.text('Equal'), findsOneWidget);
      expect(find.text('Shares'), findsOneWidget);
      expect(
        find.text('Items'),
        findsNothing,
        reason: 'spec §5.1 rules itemized out for templates',
      );
    });

    testWidgets('explains what a short month does to the anchor day',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring/new');

      await scrollTo(tester, find.textContaining('moves to the last day'));
      expect(
        find.textContaining('moves to the last day'),
        findsOneWidget,
      );
    });

    testWidgets('saving sends the cadence and the participants',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring/new');

      await fillForm(tester, title: 'Rent', amount: '30000');

      await tester.tap(find.widgetWithText(FilledButton, 'Set it up'));
      await tester.pumpAndSettle();

      expect(harness.recurring.calls, contains('create'));
      final draft = harness.recurring.lastDraft!;
      expect(draft.title, 'Rent');
      expect(draft.total, const Money(3000000));
      expect(draft.frequency, RecurrenceFrequency.monthly);
      expect(draft.participants.map((p) => p.userId), ['bea', 'carlo']);
      expect(
        draft.anchorDay,
        isNotNull,
        reason: 'a monthly template needs its day of the month',
      );
    });

    testWidgets('a weekly template carries no anchor day', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring/new');

      await fillForm(tester, title: 'Wifi', amount: '500');

      await scrollTo(tester, find.text('Weekly'));
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Set it up'));
      await tester.pumpAndSettle();

      final draft = harness.recurring.lastDraft!;
      expect(draft.frequency, RecurrenceFrequency.weekly);
      expect(draft.anchorDay, isNull);
    });

    testWidgets('saving is blocked until the split works', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/recurring/new');

      // No title and no amount yet.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Set it up'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a server refusal is shown rather than swallowed',
        (tester) async {
      final recurring = FakeRecurringRepository()
        ..saveFailure = const RecurringFailure(
          RecurringFailureKind.invalidRecurrence,
          'Pick weekly, monthly or yearly',
        );

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        recurring: recurring,
      );
      await harness.go('/groups/g1/recurring/new');

      await fillForm(tester, title: 'Rent', amount: '30000');
      await tester.tap(find.widgetWithText(FilledButton, 'Set it up'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Pick weekly, monthly or yearly'));
      expect(find.text('Pick weekly, monthly or yearly'), findsOneWidget);
    });
  });
}
