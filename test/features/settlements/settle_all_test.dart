import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/core/images/image_gallery.dart';
import 'package:hati/features/bills/domain/bill_models.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/profile/domain/payment_method.dart';
import 'package:hati/features/settlements/domain/payment.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_image_services.dart';
import '../../support/fake_payment_methods_repository.dart';
import '../../support/fake_payments_repository.dart';

final _members = [
  for (final (i, id) in ['bea', 'carlo', 'dana'].indexed)
    GroupMember(
      userId: id,
      displayName: id[0].toUpperCase() + id.substring(1),
      role: i == 0 ? 'owner' : 'member',
      joinedAt: DateTime.utc(2026, 1, i + 1),
    ),
];

FakeGroupsRepository _groups() => FakeGroupsRepository(
  groups: const [
    GroupSummary(
      id: 'g1',
      name: 'Tagaytay Staycation',
      role: 'member',
      memberCount: 3,
    ),
  ],
  members: _members,
);

/// A second bill Bea paid, with its own share ids.
Bill _samgyup({String carloStatus = 'unpaid'}) => airbnbBill(
  id: 'bill-2',
  shares: [
    const BillShare(
      id: 's21',
      userId: 'bea',
      amount: Money(150000),
      status: 'settled',
    ),
    BillShare(
      id: 's22',
      userId: 'carlo',
      amount: const Money(150000),
      status: carloStatus,
    ),
  ],
).copyWith(title: 'Samgyup', totalAmount: const Money(300000));

FakePaymentMethodsRepository _methods() => FakePaymentMethodsRepository(
  methods: const [
    PaymentMethod(
      id: 'pm1',
      userId: 'bea',
      type: 'gcash',
      accountName: 'Bea Reyes',
      accountNumber: '0917 123 4567',
      isDefault: true,
    ),
    PaymentMethod(
      id: 'pm2',
      userId: 'bea',
      type: 'gotyme',
      accountName: 'Bea Reyes',
      accountNumber: '0998 765 4321',
    ),
  ],
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

void main() {
  group('a default wallet to be paid on (DECISIONS D-66)', () {
    testWidgets('settle-up shows only the payer\'s default', (tester) async {
      final methods = _methods()..preferred['bea'] = 'pm2';
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: methods,
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text('Bea asked to be paid through GoTyme.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('a wallet chosen on the bill wins over the default', (
      tester,
    ) async {
      final methods = _methods()..preferred['bea'] = 'pm2';
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          bills: [airbnbBill().copyWith(receiveMethodId: 'pm1')],
        ),
        paymentMethods: methods,
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text('Bea asked to be paid through GCash.'), findsOneWidget);
    });

    testWidgets('is chosen on the Payment methods screen', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        paymentMethods: _methods(),
      );
      await harness.go('/profile/payment-methods');

      expect(find.text('Ask people to pay you via'), findsWidgets);
      expect(
        find.text('People settling up can use any wallet you have added.'),
        findsOneWidget,
      );
    });

    testWidgets('the bill card names the default as its fallback', (
      tester,
    ) async {
      final methods = _methods()..preferred['bea'] = 'pm2';
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: methods,
      );
      await harness.go('/bills/bill-1');

      expect(
        find.text('They will only see your GoTyme details.'),
        findsOneWidget,
      );
    });
  });

  group('Settle all with one person (DECISIONS D-67)', () {
    testWidgets('appears when you owe someone on two or more bills', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill(), _samgyup()]),
      );
      await harness.go('/groups/g1');
      await _tapVisible(tester, find.text('Balances'));

      expect(
        find.widgetWithText(FilledButton, 'Settle all with Bea · ₱4,625.00'),
        findsOneWidget,
      );
    });

    testWidgets('not for a single bill, or one already awaiting confirmation', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(
          bills: [
            airbnbBill(),
            _samgyup(carloStatus: 'pending_confirmation'),
          ],
        ),
      );
      await harness.go('/groups/g1');
      await _tapVisible(tester, find.text('Balances'));

      expect(find.textContaining('Settle all'), findsNothing);
    });

    testWidgets('pays every bill with one screenshot', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill(), _samgyup()]),
        paymentMethods: _methods(),
        surfaceSize: const Size(400, 1400),
      );
      await harness.go('/groups/g1');
      await _tapVisible(tester, find.text('Balances'));
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Settle all with Bea · ₱4,625.00'),
      );

      expect(find.text('₱4,625.00'), findsOneWidget);
      expect(find.textContaining('2 bills'), findsOneWidget);

      await _attachProof(tester);
      await _tapVisible(tester, find.widgetWithText(FilledButton, "I've paid"));

      expect(harness.payments.calls, contains('markPaidBatch'));
      expect(harness.payments.lastArgs['billShareIds'], ['s2', 's22']);
      expect(harness.payments.lastArgs['method'], 'gcash');
      expect(harness.storage.uploads, hasLength(1), reason: 'one screenshot');
      expect(
        find.text('Marked 2 bills as paid — Bea will confirm.'),
        findsOneWidget,
      );
    });

    testWidgets('the payer confirms the whole payment at once', (tester) async {
      Payment pending(String id, String shareId, int centavos) => Payment(
        id: id,
        billShareId: shareId,
        fromUser: 'carlo',
        toUser: 'bea',
        amount: Money(centavos),
        status: 'pending',
        method: 'gcash',
        batchId: 'batch-1',
        createdAt: DateTime.utc(2026, 9, 21, 10),
      );
      final payments = FakePaymentsRepository(
        payments: [pending('p1', 's2', 312500), pending('p2', 's22', 150000)],
      );
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(
          bills: [
            airbnbBill(
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
            ),
          ],
        ),
        payments: payments,
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.text('Review'));

      expect(find.textContaining('One payment for 2 bills'), findsOneWidget);
      await _tapVisible(
        tester,
        find.textContaining('Confirm ₱4,625.00 received'),
      );

      expect(harness.payments.calls, contains('confirmBatch'));
      expect(harness.payments.lastArgs['batchId'], 'batch-1');
    });
  });

  group('Save QR (DECISIONS D-68)', () {
    PaymentMethod withQr() => const PaymentMethod(
      id: 'pm1',
      userId: 'bea',
      type: 'gcash',
      accountName: 'Bea Reyes',
      accountNumber: '0917 123 4567',
      qrImagePath: 'bea/qr.png',
      isDefault: true,
    );

    testWidgets('saves the payer\'s QR to the gallery', (tester) async {
      final gallery = FakeImageGallery();
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(methods: [withQr()]),
        gallery: gallery,
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await _tapVisible(tester, find.widgetWithText(TextButton, 'Save QR'));

      expect(harness.storage.downloads.single.path, 'bea/qr.png');
      expect(gallery.saved.single, contains('GCash'));
      expect(find.textContaining('QR saved to your gallery'), findsOneWidget);
    });

    testWidgets('explains when photo access is refused', (tester) async {
      final gallery = FakeImageGallery()
        ..failWith = const GalleryFailure(
          'Hati needs permission to save photos. Allow it in Settings.',
        );
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(methods: [withQr()]),
        gallery: gallery,
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await _tapVisible(tester, find.widgetWithText(TextButton, 'Save QR'));

      expect(find.textContaining('Allow it in Settings'), findsOneWidget);
    });

    testWidgets('is not offered when there is no QR', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: _methods(),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.text('Save QR'), findsNothing);
    });
  });

  group('paying in cash (DECISIONS D-70)', () {
    testWidgets('needs no screenshot, and is sent as cash', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: _methods(),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await _tapVisible(tester, find.text('Cash'));

      expect(find.text('Attach screenshot'), findsNothing);
      expect(find.text('0917 123 4567'), findsNothing, reason: 'no QR to scan');
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'I paid in cash'),
      );

      expect(harness.payments.calls, contains('markPaid'));
      expect(harness.payments.lastArgs['method'], 'cash');
      expect(harness.payments.lastArgs['proofPath'], isNull);
      expect(harness.storage.uploads, isEmpty);
    });

    testWidgets('switching back to a wallet needs the screenshot again', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: _methods(),
      );
      await harness.go('/bills/bill-1');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await _tapVisible(tester, find.text('Cash'));
      await _tapVisible(tester, find.text('Wallet or bank'));

      final paid = find.widgetWithText(FilledButton, "I've paid");
      await tester.ensureVisible(paid);
      expect(tester.widget<FilledButton>(paid).onPressed, isNull);
    });

    testWidgets('settles several bills in cash at once', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill(), _samgyup()]),
        paymentMethods: _methods(),
      );
      await harness.go('/groups/g1');
      await _tapVisible(tester, find.text('Balances'));
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Settle all with Bea · ₱4,625.00'),
      );

      await _tapVisible(tester, find.text('Cash'));
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'I paid in cash'),
      );

      expect(harness.payments.calls, contains('markPaidBatch'));
      expect(harness.payments.lastArgs['method'], 'cash');
      expect(harness.payments.lastArgs['proofPath'], isNull);
    });
  });
}
