import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/features/bills/domain/bill_models.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/profile/domain/payment_method.dart';
import 'package:hati/features/settlements/domain/payment.dart';
import 'package:hati/features/settlements/domain/settlement_failure.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_payment_methods_repository.dart';
import '../../support/fake_payments_repository.dart';

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

const _beaGcash = PaymentMethod(
  id: 'pm1',
  userId: 'bea',
  type: 'gcash',
  accountName: 'Bea Reyes',
  accountNumber: '0917 123 4567',
  isDefault: true,
);

const _beaGotyme = PaymentMethod(
  id: 'pm2',
  userId: 'bea',
  type: 'gotyme',
  accountName: 'Bea Reyes',
  accountNumber: '0998 765 4321',
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _attachProof(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.widgetWithText(OutlinedButton, 'Attach screenshot'),
  );
  await _tapVisible(tester, find.text('Choose from gallery'));
}

Payment _pendingFromCarlo() => Payment(
  id: 'pay-1',
  billShareId: 's2',
  fromUser: 'carlo',
  toUser: 'bea',
  amount: const Money(312500),
  status: 'pending',
  method: 'gcash',
  referenceNo: 'REF123',
  createdAt: DateTime.utc(2026, 9, 21, 10),
);

void main() {
  group('Settle up (spec §9)', () {
    testWidgets('a debtor is offered Settle up on their own share', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.widgetWithText(FilledButton, 'Settle up'), findsOneWidget);
    });

    testWidgets('the payer is not offered Settle up on their own bill', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.widgetWithText(FilledButton, 'Settle up'), findsNothing);
    });

    testWidgets("the page shows the payer's details and the amount owed", (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(methods: [_beaGcash]),
      );
      await harness.go('/bills/bill-1');

      await tester.tap(find.widgetWithText(FilledButton, 'Settle up'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Settle up'), findsOneWidget);
      expect(find.text('You owe Bea'), findsWidgets);
      expect(find.text('0917 123 4567'), findsOneWidget);
      expect(find.text('Open GCash'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, "I've paid"), findsOneWidget);
    });

    testWidgets('a payer with no details still lets you mark it paid', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(
        find.textContaining("hasn't added payment details"),
        findsOneWidget,
      );

      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Other'));
      await _attachProof(tester);
      await _tapVisible(tester, find.widgetWithText(FilledButton, "I've paid"));

      expect(harness.payments.calls, contains('markPaid'));
      expect(harness.payments.lastArgs['method'], 'other');
    });

    testWidgets("I've paid sends the wallet, reference and proof", (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(methods: [_beaGcash]),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Reference number'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reference number'),
        'REF123',
      );
      await _attachProof(tester);
      await _tapVisible(tester, find.widgetWithText(FilledButton, "I've paid"));

      expect(harness.payments.calls, contains('markPaid'));
      expect(harness.payments.lastArgs['method'], 'gcash');
      expect(harness.payments.lastArgs['referenceNo'], 'REF123');
      expect(harness.payments.lastArgs['billShareId'], 's2');
      expect(harness.payments.lastArgs['proofPath'], startsWith('g1/'));
      expect(find.text('Marked as paid — Bea will confirm.'), findsOneWidget);
    });
  });

  group('Choosing where to be paid', () {
    testWidgets('with any wallet allowed, the debtor picks which QR to use', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(
          methods: [_beaGcash, _beaGotyme],
        ),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text("Pay through any of Bea's wallets."), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'GCash'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'GoTyme'), findsOneWidget);
      // The default wallet is on show first.
      expect(find.text('0917 123 4567'), findsOneWidget);

      await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'GoTyme'));
      expect(find.text('0998 765 4321'), findsOneWidget);
      expect(find.text('0917 123 4567'), findsNothing);

      await _attachProof(tester);
      await _tapVisible(tester, find.widgetWithText(FilledButton, "I've paid"));
      expect(harness.payments.lastArgs['method'], 'gotyme');
    });

    testWidgets('a wallet the payer asked for is the only one shown', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          bills: [airbnbBill().copyWith(receiveMethodId: 'pm2')],
        ),
        paymentMethods: FakePaymentMethodsRepository(
          methods: [_beaGcash, _beaGotyme],
        ),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text('Bea asked to be paid through GoTyme.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('0998 765 4321'), findsOneWidget);
      expect(find.text('0917 123 4567'), findsNothing);
    });

    testWidgets('a pinned wallet that was deleted falls back to any', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          bills: [airbnbBill().copyWith(receiveMethodId: 'gone')],
        ),
        paymentMethods: FakePaymentMethodsRepository(
          methods: [_beaGcash, _beaGotyme],
        ),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text("Pay through any of Bea's wallets."), findsOneWidget);
    });

    testWidgets('the payer chooses which wallet debtors see', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(
          methods: [_beaGcash, _beaGotyme],
        ),
      );
      await harness.go('/bills/bill-1');

      expect(find.text('Where should they pay you?'), findsOneWidget);
      expect(
        find.text('They can scan the QR of any wallet you have added.'),
        findsOneWidget,
      );

      await _tapVisible(tester, find.byKey(const ValueKey('receive-method')));
      await _tapVisible(tester, find.text('GoTyme').last);

      expect(harness.payments.calls, contains('setReceiveMethod'));
      expect(harness.payments.lastArgs, {
        'billId': 'bill-1',
        'methodId': 'pm2',
      });
    });

    testWidgets('a payer with no wallets is pointed at adding one', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(
        find.widgetWithText(OutlinedButton, 'Add payment methods'),
        findsOneWidget,
      );
    });

    testWidgets('a debtor is never asked where to be paid', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(methods: [_beaGcash]),
      );
      await harness.go('/bills/bill-1');

      expect(find.text('Where should they pay you?'), findsNothing);
    });
  });

  group('Review (spec §14)', () {
    testWidgets('only the payer is offered Review on a pending claim', (
      tester,
    ) async {
      final bill = airbnbBill(
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

      final asPayer = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [bill]),
        payments: FakePaymentsRepository(payments: [_pendingFromCarlo()]),
      );
      await asPayer.go('/bills/bill-1');
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('the debtor sees only that they are waiting', (tester) async {
      final bill = airbnbBill(
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

      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [bill]),
        payments: FakePaymentsRepository(payments: [_pendingFromCarlo()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.text('Review'), findsNothing);
      expect(find.text('Waiting for Bea to confirm.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Settle up'), findsNothing);
    });

    testWidgets('confirming sends the payment id', (tester) async {
      final bill = airbnbBill(
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

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [bill]),
        payments: FakePaymentsRepository(payments: [_pendingFromCarlo()]),
      );
      await harness.go('/bills/bill-1');

      await _tapVisible(tester, find.text('Review'));

      expect(find.text('Carlo says they paid'), findsOneWidget);
      expect(find.text('REF123'), findsOneWidget);

      await tester.tap(find.textContaining('Confirm ₱3,125.00 received'));
      await tester.pumpAndSettle();

      expect(harness.payments.calls, contains('confirm'));
      expect(harness.payments.lastArgs['paymentId'], 'pay-1');
    });

    testWidgets('rejecting asks for a reason and sends it', (tester) async {
      final bill = airbnbBill(
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

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [bill]),
        payments: FakePaymentsRepository(payments: [_pendingFromCarlo()]),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.text('Review'));

      await tester.tap(find.widgetWithText(TextButton, "I didn't get it"));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, "What's wrong?"),
        'Nothing arrived in GCash',
      );
      await tester.tap(find.widgetWithText(FilledButton, "I didn't get it"));
      await tester.pumpAndSettle();

      expect(harness.payments.calls, contains('reject'));
      expect(harness.payments.lastArgs['reason'], 'Nothing arrived in GCash');
    });
  });

  group('Record cash (spec §7)', () {
    testWidgets('the payer can record cash against an unpaid share', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      // Record cash and Nudge share one menu per unpaid share.
      expect(find.byTooltip('Options for Carlo'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Carlo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record cash'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      expect(harness.payments.calls, contains('recordReceived'));
    });

    testWidgets('a debtor is never offered Record cash', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      expect(find.byTooltip('Options for Bea'), findsNothing);
      expect(find.text('Record cash'), findsNothing);
    });
  });

  group('SettlementFailure', () {
    test('maps every settlement code the RPCs raise', () {
      const expected = {
        'HT040': SettlementFailureKind.shareNotFound,
        'HT041': SettlementFailureKind.notTheDebtor,
        'HT042': SettlementFailureKind.notThePayer,
        'HT043': SettlementFailureKind.shareAlreadySettled,
        'HT044': SettlementFailureKind.paymentNotFound,
        'HT045': SettlementFailureKind.alreadyDecided,
        'HT046': SettlementFailureKind.billVoided,
        'HT047': SettlementFailureKind.proofRequired,
        'HT048': SettlementFailureKind.notYourMethod,
      };
      expected.forEach((code, kind) {
        expect(SettlementFailure.fromCode(code, 'x').kind, kind, reason: code);
      });
    });

    test('explains who is allowed to confirm', () {
      expect(
        SettlementFailure.fromCode('HT042', 'raw').displayMessage,
        contains('Only whoever paid the bill'),
      );
    });
  });

  group('Payment', () {
    test('labels each method for display', () {
      Payment withMethod(String? method) => Payment(
        id: 'p',
        billShareId: 's',
        fromUser: 'a',
        toUser: 'b',
        amount: const Money(100),
        status: 'pending',
        method: method,
      );

      expect(withMethod('gcash').methodLabel, 'GCash');
      expect(withMethod('maya').methodLabel, 'Maya');
      expect(withMethod('bank').methodLabel, 'Bank transfer');
      expect(withMethod('gotyme').methodLabel, 'GoTyme');
      expect(withMethod('shopeepay').methodLabel, 'ShopeePay');
      expect(withMethod('coinsph').methodLabel, 'Coins.ph');
      expect(withMethod('cash').methodLabel, 'Cash');
      expect(withMethod(null).methodLabel, 'Other');
    });
  });
}
