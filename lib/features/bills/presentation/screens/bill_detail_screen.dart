import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../groups/domain/group_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../../../activity/presentation/activity_controller.dart';
import '../../../activity/presentation/widgets/comment_thread.dart';
import '../../../notifications/presentation/notifications_controller.dart';
import '../../../profile/data/payment_methods_repository.dart';
import '../../../profile/domain/payment_method.dart';
import '../../../settlements/domain/payment.dart';
import '../../../settlements/presentation/settlements_controller.dart';
import '../../../settlements/presentation/widgets/payment_review_sheet.dart';
import '../../../settlements/presentation/screens/settle_up_screen.dart';
import '../../domain/bill_models.dart';
import '../bills_controller.dart';

/// Bill detail (spec §10).
///
/// Settle up, Confirm and Reject arrive with M5; what is here is the bill, who
/// owes what, and the edit/void actions.
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({required this.billId, super.key});

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bill = ref.watch(billDetailProvider(billId));
    final userId = ref.watch(sessionStateProvider).userId;

    // Live while this screen is open, closed when it goes away (spec §4.3).
    ref.watch(billRealtimeProvider(billId));

    return bill.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(
          message: 'Could not load this bill.',
          onRetry: () => ref.invalidate(billDetailProvider(billId)),
        ),
      ),
      data: (loaded) => _Loaded(bill: loaded, currentUserId: userId ?? ''),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.bill, required this.currentUserId});

  final Bill bill;
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(groupMembersProvider(bill.groupId));
    final memberList = members.asData?.value ?? const <GroupMember>[];
    final names = {for (final m in memberList) m.userId: m.displayName};
    final avatars = {for (final m in memberList) m.userId: m.avatarPath};
    final payerName = names[bill.paidBy] ?? 'Someone';
    final myShare = bill.shareFor(currentUserId);
    final iAmPayer = bill.paidBy == currentUserId;
    final payments = ref.watch(billPaymentsProvider(bill.id));

    // The claim currently awaiting a decision, per share.
    final pendingByShare = <String, Payment>{
      for (final payment in payments.asData?.value ?? const <Payment>[])
        if (payment.isPending) payment.billShareId: payment,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(bill.title, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'edit' => context.push(Routes.editBill(bill.groupId, bill.id)),
              'void' => _confirmVoid(context, ref),
              _ => null,
            },
            itemBuilder: (_) => [
              if (bill.canEdit(currentUserId))
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!bill.isVoid)
                const PopupMenuItem(value: 'void', child: Text('Void bill')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: kPagePadding,
        children: [
          if (bill.isVoid)
            const Padding(
              padding: EdgeInsets.only(bottom: kSpace * 2),
              child: InfoNote(
                icon: Icons.block,
                message: 'This bill was voided.',
              ),
            ),

          const SizedBox(height: kSpace),
          AmountText(
            bill.totalAmount,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: kSpace / 2),
          Text(
            '${iAmPayer ? 'You' : payerName} paid · '
            '${DateFormat.yMMMd('en_PH').format(bill.billDate)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (bill.notes != null && bill.notes!.isNotEmpty) ...[
            const SizedBox(height: kSpace * 2),
            Text(bill.notes!, style: theme.textTheme.bodyMedium),
          ],

          if (bill.attachments.isNotEmpty) ...[
            const SizedBox(height: kSpace * 3),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bill.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: kSpace * 1.5),
                itemBuilder: (_, index) {
                  final attachment = bill.attachments[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(kRadiusMd),
                    child: AttachmentImage(
                      bucket: StorageBucket.billReceipts,
                      path: attachment.path,
                      width: 96,
                      height: 96,
                      semanticLabel:
                          'Receipt ${index + 1} of ${bill.attachments.length}',
                    ),
                  );
                },
              ),
            ),
          ],

          if (myShare != null && !bill.isVoid) ...[
            const SizedBox(height: kSpace * 3),
            _MyShareCard(
              bill: bill,
              share: myShare,
              isPayer: iAmPayer,
              payerName: payerName,
            ),
          ],

          // Only worth asking while someone still has to pay.
          if (iAmPayer &&
              !bill.isVoid &&
              bill.shares.any((s) => s.userId != bill.paidBy && !s.isSettled)) ...[
            const SizedBox(height: kSpace * 2),
            _ReceiveMethodCard(bill: bill),
          ],

          const SectionHeader('Who owes what'),
          ListGroup(
            dividerIndent: 72,
            children: [
              for (final share in bill.shares)
                _ShareRow(
                  bill: bill,
                  share: share,
                  name: share.userId == currentUserId
                      ? 'You'
                      : names[share.userId] ?? 'Someone',
                  avatarPath: avatars[share.userId],
                  isPayer: share.userId == bill.paidBy,
                  // Only the payer decides on a claim or records cash
                  // (spec §14).
                  viewerIsPayer: iAmPayer && !bill.isVoid,
                  pendingPayment: pendingByShare[share.id],
                ),
            ],
          ),

          if (bill.items.isNotEmpty) ...[
            const SectionHeader('Items'),
            ListGroup(
              children: [
                for (final item in bill.items)
                  ListTile(
                    title: Text(item.name),
                    subtitle: Text(
                      item.assignees
                          .map((id) => names[id] ?? 'Someone')
                          .join(', '),
                    ),
                    trailing: AmountText(
                      item.amount,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                if (!bill.extras.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: kSpace,
                    ),
                    child: Column(
                      children: [
                        if (bill.extras.serviceCharge > 0)
                          _ExtraRow(
                            'Service charge',
                            bill.extras.serviceCharge,
                          ),
                        if (bill.extras.tax > 0)
                          _ExtraRow('Tax', bill.extras.tax),
                        if (bill.extras.discount > 0)
                          _ExtraRow('Discount', -bill.extras.discount),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: kSpace * 3),
          CommentThread(billId: bill.id, currentUserId: currentUserId),

          const SizedBox(height: kSpace * 4),
        ],
      ),
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(billActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void this bill?'),
        content: const Text(
          'It stays in the group history but stops counting towards anyone '
          "balance. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Void bill'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await actions.voidBill(billId: bill.id, groupId: bill.groupId);

    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(actions.lastError ?? 'Could not void the bill.'),
        ),
      );
    }
  }
}

/// The payer chooses where debtors should send the money on this bill: one
/// wallet, whose QR the settle-up page then shows on its own, or any of them.
class _ReceiveMethodCard extends ConsumerWidget {
  const _ReceiveMethodCard({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final methods = ref.watch(paymentMethodsForProvider(bill.paidBy));
    final list = methods.asData?.value ?? const <PaymentMethod>[];

    PaymentMethod? chosen;
    PaymentMethod? preferred;
    final preferredId = ref
        .watch(preferredReceiveMethodProvider(bill.paidBy))
        .asData
        ?.value;
    for (final method in list) {
      if (method.id == bill.receiveMethodId) chosen = method;
      if (method.id == preferredId) preferred = method;
    }
    // With no choice on this bill, their default applies (D-66).
    final effective = chosen ?? preferred;

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where should they pay you?',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: kSpace),
            if (methods.isLoading)
              const LinearProgressIndicator()
            else if (list.isEmpty) ...[
              Text(
                'Add your GCash, Maya or other wallet QR codes so your '
                'barkada can scan and pay.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: kSpace),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.paymentMethods),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Add payment methods'),
              ),
            ] else
              DropdownMenu<String?>(
                key: const ValueKey('receive-method'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: chosen?.id,
                label: const Text('Receive payment via'),
                leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
                onSelected: (id) => _choose(context, ref, id),
                dropdownMenuEntries: [
                  DropdownMenuEntry<String?>(
                    value: null,
                    label: preferred == null
                        ? 'Any of my wallets'
                        : 'My default (${preferred.displayLabel})',
                  ),
                  for (final method in list)
                    DropdownMenuEntry<String?>(
                      value: method.id,
                      label: method.displayLabel,
                      trailingIcon:
                          method.hasQr ? const Icon(Icons.qr_code_2) : null,
                    ),
                ],
              ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: kSpace),
              Text(
                effective == null
                    ? 'They can scan the QR of any wallet you have added.'
                    : 'They will only see your ${effective.displayLabel} '
                        'details.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, String? id) async {
    if (id == bill.receiveMethodId) return;

    final actions = ref.read(settlementActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await actions.setReceiveMethod(
      billId: bill.id,
      groupId: bill.groupId,
      methodId: id,
    );
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            actions.lastError ?? 'Could not save where to be paid.',
          ),
        ),
      );
    }
  }
}

class _MyShareCard extends ConsumerWidget {
  const _MyShareCard({
    required this.bill,
    required this.share,
    required this.isPayer,
    required this.payerName,
  });

  final Bill bill;
  final BillShare share;
  final bool isPayer;
  final String payerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = context.money;

    if (isPayer) {
      // A note, not a card: there is nothing to do here.
      return const InfoNote(
        icon: Icons.check_circle_outline,
        message: 'You paid for this. Your own share is settled.',
      );
    }

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              share.isSettled ? 'You are all square' : 'You owe $payerName',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: kSpace / 2),
            AmountText(
              share.amount,
              style: theme.textTheme.headlineMedium,
              color: share.isSettled ? money.owed : money.owe,
            ),
            const SizedBox(height: kSpace),
            Text(
              share.statusLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (share.isUnpaid) ...[
              const SizedBox(height: kSpace * 2),
              FilledButton(
                onPressed: () => SettleUpScreen.show(
                  context,
                  bill: bill,
                  share: share,
                  payerName: payerName,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Settle up'),
              ),
            ],
            if (share.isAwaitingConfirmation) ...[
              const SizedBox(height: kSpace),
              Text(
                'Waiting for $payerName to confirm.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: money.pending,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends ConsumerWidget {
  const _ShareRow({
    required this.bill,
    required this.share,
    required this.name,
    required this.avatarPath,
    required this.isPayer,
    required this.viewerIsPayer,
    required this.pendingPayment,
  });

  final Bill bill;
  final BillShare share;
  final String name;
  final String? avatarPath;
  final bool isPayer;
  final bool viewerIsPayer;
  final Payment? pendingPayment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = context.money;

    final (colour, label) = switch (share.status) {
      'settled' => (money.owed, isPayer ? 'Paid the bill' : 'Settled'),
      'pending_confirmation' => (money.pending, 'Awaiting confirmation'),
      _ => (money.owe, 'Unpaid'),
    };

    return Semantics(
      label: '$name, ${share.amount.format()}, $label',
      excludeSemantics: true,
      child: ListTile(
        leading: UserAvatar(displayName: name, avatarPath: avatarPath),
        title: Text(name),
        // Never colour alone (spec §11): the status is spelled out too.
        subtitle: Align(
          alignment: Alignment.centerLeft,
          child: StatusLabel(label, color: colour),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AmountText(share.amount, style: theme.textTheme.titleSmall),
            if (viewerIsPayer && !isPayer && pendingPayment != null) ...[
              const SizedBox(width: kSpace),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => PaymentReviewSheet.show(
                  context,
                  payment: pendingPayment!,
                  billId: bill.id,
                  groupId: bill.groupId,
                  debtorName: name,
                ),
                child: const Text('Review'),
              ),
            ] else if (viewerIsPayer && !isPayer && share.isUnpaid) ...[
              const SizedBox(width: kSpace),
              PopupMenuButton<String>(
                tooltip: 'Options for $name',
                onSelected: (value) => value == 'cash'
                    ? _recordCash(context, ref)
                    : _nudge(context, ref),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cash', child: Text('Record cash')),
                  PopupMenuItem(value: 'nudge', child: Text('Nudge')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A gentle prod, at most once a day per share (spec §7.2).
  Future<void> _nudge(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(notificationActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await actions.nudge(
      billShareId: share.id,
      billId: bill.id,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Nudged $name.' : actions.lastError ?? 'Could not nudge.',
        ),
      ),
    );
  }

  /// Cash handed over in person: the payer records it and it settles at once
  /// (spec §7 record_payment_received).
  Future<void> _recordCash(BuildContext context, WidgetRef ref) async {
    // Captured now: recordCash invalidates the provider that built this row,
    // so `ref` may be disposed once the future completes.
    final actions = ref.read(settlementActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record $name as paid?'),
        content: Text(
          'Use this when $name handed you the money directly. It settles '
          'their share straight away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await actions.recordCash(
      billShareId: share.id,
      billId: bill.id,
      groupId: bill.groupId,
    );

    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'Could not record that.')),
      );
    }
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow(this.label, this.centavos);

  final String label;
  final int centavos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          AmountText(
            Money(centavos),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
