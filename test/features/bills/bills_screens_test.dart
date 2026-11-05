import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/features/bills/domain/bill_failure.dart';
import 'package:hati/features/bills/domain/bill_models.dart';
import 'package:hati/features/groups/domain/group_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';

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
  GroupMember(
    userId: 'dana',
    displayName: 'Dana',
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 3),
  ),
  GroupMember(
    userId: 'eli',
    displayName: 'Eli',
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 4),
  ),
];

FakeGroupsRepository _groups() => FakeGroupsRepository(
      groups: const [
        GroupSummary(
          id: 'g1',
          name: 'Tagaytay Staycation',
          role: 'member',
          memberCount: 4,
        ),
      ],
      members: _members,
    );

void main() {
  group('Home (spec §10)', () {
    testWidgets('shows what you owe and what you are owed', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          balances: const [
            GroupBalance(
              groupId: 'g1',
              groupName: 'Tagaytay Staycation',
              owedByMe: Money(312500),
              owedToMe: Money.zero,
            ),
          ],
        ),
      );

      expect(find.text('You owe'), findsOneWidget);
      expect(find.text("You're owed"), findsOneWidget);
      expect(find.text('₱3,125.00'), findsWidgets);
    });

    testWidgets('celebrates when nothing is outstanding', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          balances: const [
            GroupBalance(
              groupId: 'g1',
              groupName: 'Tagaytay Staycation',
              owedByMe: Money.zero,
              owedToMe: Money.zero,
            ),
          ],
        ),
      );

      expect(find.text("You're all square!"), findsOneWidget);
    });

    testWidgets('lists what needs attention', (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          balances: const [
            GroupBalance(
              groupId: 'g1',
              groupName: 'Tagaytay Staycation',
              owedByMe: Money(312500),
              owedToMe: Money.zero,
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
        ),
      );

      expect(find.text('Needs your attention'), findsOneWidget);
      expect(find.text('Airbnb – 2 nights'), findsOneWidget);
      expect(
        find.textContaining('pay Bea'),
        findsOneWidget,
        reason: 'the row should say what to do, not just the amount',
      );
    });
  });

  group('the reference scenario (spec §1)', () {
    testWidgets('a member sees they owe Bea ₱3,125.00', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.text('You owe Bea'), findsOneWidget);
      expect(find.text('₱3,125.00'), findsWidgets);
      expect(find.text('₱12,500.00'), findsOneWidget);
    });

    testWidgets("the payer's own share reads as settled", (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(
        find.text('You paid for this. Your own share is settled.'),
        findsOneWidget,
      );
      expect(find.text('Paid the bill'), findsOneWidget);
      expect(find.text('Unpaid'), findsNWidgets(3));
    });
  });

  group('Bills tab', () {
    testWidgets('offers one clear action when there are no bills',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
      );
      await harness.go('/groups/g1');

      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add bill'), findsOneWidget);
    });

    testWidgets('a bill card says what the viewer owes', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/groups/g1');

      expect(find.text('You owe ₱3,125.00'), findsOneWidget);
      expect(find.textContaining('Bea paid'), findsOneWidget);
    });

    testWidgets('the payer sees what is owed to them instead', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/groups/g1');

      expect(find.text('₱9,375.00 owed to you'), findsOneWidget);
    });
  });

  group('Balances tab', () {
    testWidgets('lists who owes whom, per bill, without netting',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/groups/g1');
      await tester.tap(find.text('Balances'));
      await tester.pumpAndSettle();

      expect(find.text('You owe'), findsOneWidget);
      expect(find.text('Dana owes'), findsOneWidget);
      expect(find.textContaining('to Bea'), findsWidgets);
    });
  });

  group('editing rules (spec §12.1)', () {
    test('a bill with money in flight cannot be edited', () {
      final locked = airbnbBill(
        shares: const [
          BillShare(
            id: 's1',
            userId: 'bea',
            amount: Money(312500),
            status: 'settled',
          ),
          BillShare(
            id: 's2',
            userId: 'carlo',
            amount: Money(312500),
            status: 'pending_confirmation',
          ),
        ],
      );
      expect(locked.canEdit('bea'), isFalse);
    });

    test('a settled share also locks it', () {
      final settled = airbnbBill(
        shares: const [
          BillShare(
            id: 's1',
            userId: 'bea',
            amount: Money(312500),
            status: 'settled',
          ),
          BillShare(
            id: 's2',
            userId: 'carlo',
            amount: Money(312500),
            status: 'settled',
          ),
        ],
      );
      expect(settled.canEdit('bea'), isFalse);
    });

    test('an untouched bill can be edited by its creator or payer', () {
      final bill = airbnbBill();
      expect(bill.canEdit('bea'), isTrue);
      expect(bill.canEdit('carlo'), isFalse);
    });

    test('a voided bill can never be edited', () {
      expect(airbnbBill(status: 'void').canEdit('bea'), isFalse);
    });
  });

  group('BillFailure', () {
    test('keeps the split engine range apart from the bill range', () {
      final split = BillFailure.fromCode('HT024', 'percent_sum_mismatch');
      expect(split.kind, BillFailureKind.splitInvalid);
      expect(split.displayMessage, contains('100%'));

      final locked = BillFailure.fromCode('HT033', 'someone paid');
      expect(locked.kind, BillFailureKind.lockedByPayment);
      expect(locked.displayMessage, contains('Void this bill'));
    });

    test('maps every bill code the RPCs raise', () {
      const expected = {
        'HT030': BillFailureKind.billNotFound,
        'HT031': BillFailureKind.payerNotMember,
        'HT032': BillFailureKind.participantNotMember,
        'HT033': BillFailureKind.lockedByPayment,
        'HT034': BillFailureKind.hasConfirmedPayment,
        'HT035': BillFailureKind.notAllowed,
        'HT036': BillFailureKind.billVoided,
      };
      expected.forEach((code, kind) {
        expect(BillFailure.fromCode(code, 'x').kind, kind, reason: code);
      });
    });
  });

  group('Bill', () {
    test('outstanding ignores the payer and settled shares', () {
      expect(airbnbBill().outstanding, const Money(937500));
    });

    test('knows whether the viewer owes anything', () {
      final bill = airbnbBill();
      expect(bill.owedBy('carlo'), isTrue);
      expect(bill.owedBy('bea'), isFalse, reason: 'the payer owes nothing');
      expect(airbnbBill(status: 'void').owedBy('carlo'), isFalse);
    });
  });
}
