import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/images/attachment_storage.dart';
import 'package:hati/core/images/image_models.dart';
import 'package:hati/features/bills/domain/bill_models.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/profile/domain/payment_method.dart';

import '../../support/app_harness.dart';
import '../../support/fake_bills_repository.dart';
import '../../support/fake_groups_repository.dart';
import '../../support/fake_image_services.dart';
import '../../support/fake_payment_methods_repository.dart';

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

/// The test surface is 800x600, so anything down the page needs bringing into
/// view before it can be tapped.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterTextVisible(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

/// A ListView does not build what is scrolled out of view, so an assertion on
/// something off-screen has to bring it back first. [delta] is negative to
/// scroll upwards.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('bill receipts (spec §12.11)', () {
    testWidgets('picking a receipt shows a thumbnail', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/bills/new');

      expect(find.text('0 of 5'), findsOneWidget);

      await tapVisible(tester, find.byIcon(Icons.add_a_photo_outlined));
      await tapVisible(tester, find.text('Choose from gallery'));

      expect(harness.images.requested, [ImageSourceKind.gallery]);
      expect(find.text('1 of 5'), findsOneWidget);
    });

    testWidgets('the add button disappears at five', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/bills/new');

      for (var i = 0; i < 5; i++) {
        await tapVisible(tester, find.byIcon(Icons.add_a_photo_outlined));
        await tapVisible(tester, find.text('Choose from gallery'));
      }

      expect(find.text('5 of 5'), findsOneWidget);
      expect(
        find.byIcon(Icons.add_a_photo_outlined),
        findsNothing,
        reason: 'the sixth receipt should not be offered',
      );
    });

    testWidgets('backing out of the picker adds nothing', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        images: FakeImageService.cancelling(),
      );
      await harness.go('/groups/g1/bills/new');

      await tapVisible(tester, find.byIcon(Icons.add_a_photo_outlined));
      await tapVisible(tester, find.text('Take a photo'));

      expect(harness.images.requested, [ImageSourceKind.camera]);
      await scrollTo(tester, find.text('0 of 5'));
      expect(find.text('0 of 5'), findsOneWidget);
    });

    testWidgets('saving uploads under the group and bill, then records them',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
      );
      await harness.go('/groups/g1/bills/new');

      await enterTextVisible(tester, find.widgetWithText(TextField, 'What was it for?'), 'Airbnb');
      await enterTextVisible(
        tester,
        find.widgetWithText(TextFormField, 'Total'),
        '100',
      );

      await tapVisible(tester, find.byIcon(Icons.add_a_photo_outlined));
      await tapVisible(tester, find.text('Choose from gallery'));

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Add bill'));

      expect(harness.bills.calls, contains('createBill'));
      expect(harness.storage.uploads, hasLength(1));

      final upload = harness.storage.uploads.single;
      expect(upload.bucket, StorageBucket.billReceipts);
      expect(
        upload.path,
        startsWith('g1/new-bill-id/'),
        reason: 'the policy authorises on the group id, and the bill id '
            'groups the receipts',
      );
      expect(harness.bills.attachedPaths, [upload.path]);
    });

    testWidgets('a failed upload is reported and leaves the bill in place',
        (tester) async {
      final storage = FakeAttachmentStorage()
        ..failWith = const AttachmentFailure('bucket full');

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        storage: storage,
      );
      await harness.go('/groups/g1/bills/new');

      await enterTextVisible(tester, find.widgetWithText(TextField, 'What was it for?'), 'Airbnb');
      await enterTextVisible(
        tester,
        find.widgetWithText(TextFormField, 'Total'),
        '100',
      );
      await tapVisible(tester, find.byIcon(Icons.add_a_photo_outlined));
      await tapVisible(tester, find.text('Choose from gallery'));

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Add bill'));

      expect(harness.bills.calls, contains('createBill'));
      expect(harness.bills.calls, isNot(contains('addAttachments')));

      // The banner sits at the top of the form, above where we scrolled to
      // reach the photo button.
      await scrollTo(
        tester,
        find.textContaining('Could not upload the receipt'),
        delta: -200,
      );
      expect(
        find.textContaining('Could not upload the receipt'),
        findsOneWidget,
      );
    });

    testWidgets('bill detail shows the receipts it has', (tester) async {
      final bill = airbnbBill().copyWith(
        attachments: const [
          BillAttachment(id: 'a1', path: 'g1/bill-1/one.jpg'),
          BillAttachment(id: 'a2', path: 'g1/bill-1/two.jpg'),
        ],
      );

      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [bill]),
      );
      await harness.go('/bills/bill-1');

      expect(find.bySemanticsLabel('Receipt 1 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Receipt 2 of 2'), findsOneWidget);
    });
  });

  group('payment proof', () {
    testWidgets('attaching a screenshot uploads it under the group',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      );
      await harness.go('/bills/bill-1');

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Attach screenshot'));
      await tapVisible(tester, find.text('Choose from gallery'));

      await tapVisible(tester, find.widgetWithText(FilledButton, "I've paid"));

      expect(harness.storage.uploads, hasLength(1));
      final upload = harness.storage.uploads.single;
      expect(upload.bucket, StorageBucket.paymentProofs);
      expect(upload.path, startsWith('g1/'));
      expect(harness.payments.calls, contains('markPaid'));
      expect(harness.payments.lastArgs['proofPath'], upload.path);
    });

    testWidgets("I've paid stays disabled until a screenshot is attached",
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        // Tall enough that the whole settle-up page is built at once.
        surfaceSize: const Size(400, 1800),
      );
      await harness.go('/bills/bill-1');

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      final paid = find.widgetWithText(FilledButton, "I've paid");
      await tester.ensureVisible(paid);
      expect(tester.widget<FilledButton>(paid).onPressed, isNull);
      expect(
        find.text('Attach a screenshot of your receipt to continue.'),
        findsOneWidget,
      );

      await tester.tap(paid);
      await tester.pumpAndSettle();
      expect(harness.storage.uploads, isEmpty);
      expect(harness.payments.calls, isNot(contains('markPaid')));

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Attach screenshot'));
      await tapVisible(tester, find.text('Choose from gallery'));

      expect(tester.widget<FilledButton>(paid).onPressed, isNotNull);
    });

    testWidgets('removing the screenshot disables I\'ve paid again',
        (tester) async {
      await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
      ).then((h) => h.go('/bills/bill-1'));

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Attach screenshot'));
      await tapVisible(tester, find.text('Choose from gallery'));

      final paid = find.widgetWithText(FilledButton, "I've paid");
      expect(tester.widget<FilledButton>(paid).onPressed, isNotNull);

      await tapVisible(tester, find.byTooltip('Remove'));
      expect(tester.widget<FilledButton>(paid).onPressed, isNull);
    });
  });

  group('payment method QR', () {
    testWidgets('a QR is uploaded under the owner id before the row is saved',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('bea'),
        groups: _groups(),
        paymentMethods: FakePaymentMethodsRepository(),
      );
      await harness.go('/profile/payment-methods');

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Add method'));

      await enterTextVisible(tester, find.widgetWithText(TextFormField, 'Account name'), 'Bea Reyes');
      await enterTextVisible(tester, find.widgetWithText(TextFormField, 'Mobile number'), '09171234567');

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Add QR screenshot'));
      await tapVisible(tester, find.text('Choose from gallery'));

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));

      expect(harness.storage.uploads, hasLength(1));
      final upload = harness.storage.uploads.single;
      expect(upload.bucket, StorageBucket.paymentQr);
      expect(upload.path, startsWith('bea/'));

      expect(harness.paymentMethods.calls, contains('save'));
      expect(harness.paymentMethods.methods.single.qrImagePath, upload.path);
    });

    testWidgets("the settle-up sheet shows the payer's QR", (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedInAs('carlo'),
        groups: _groups(),
        bills: FakeBillsRepository(bills: [airbnbBill()]),
        paymentMethods: FakePaymentMethodsRepository(
          methods: const [
            PaymentMethod(
              id: 'pm1',
              userId: 'bea',
              type: 'gcash',
              accountName: 'Bea Reyes',
              accountNumber: '0917 123 4567',
              qrImagePath: 'bea/qr.jpg',
            ),
          ],
        ),
      );
      await harness.go('/bills/bill-1');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Settle up'));

      expect(find.bySemanticsLabel('GCash QR code'), findsOneWidget);
    });
  });
}
