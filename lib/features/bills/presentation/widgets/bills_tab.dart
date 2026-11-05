import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../groups/domain/group_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../../domain/bill_models.dart';
import '../bills_controller.dart';

enum _BillFilter { open, settled, all }

/// The Bills tab of Group detail (spec §10): open first, then settled, with
/// filter chips.
class BillsTab extends ConsumerStatefulWidget {
  const BillsTab({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends ConsumerState<BillsTab> {
  _BillFilter _filter = _BillFilter.open;

  @override
  Widget build(BuildContext context) {
    final bills = ref.watch(groupBillsProvider(widget.groupId));
    final userId = ref.watch(sessionStateProvider).userId ?? '';
    final members = ref.watch(groupMembersProvider(widget.groupId));
    final names = {
      for (final m in members.asData?.value ?? const <GroupMember>[])
        m.userId: m.displayName,
    };

    return bills.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorRetry(
        message: 'Could not load the bills.',
        onRetry: () => ref.invalidate(groupBillsProvider(widget.groupId)),
      ),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No bills yet',
            message: 'Add the first one and Hati will do the maths.',
            actionLabel: 'Add bill',
            actionIcon: Icons.add,
            onAction: () =>
                context.push('/groups/${widget.groupId}/bills/new'),
          );
        }

        final visible = switch (_filter) {
          _BillFilter.open =>
            all.where((b) => !b.isVoid && b.outstanding.isPositive).toList(),
          _BillFilter.settled =>
            all.where((b) => !b.isVoid && b.outstanding.isZero).toList(),
          _BillFilter.all => all,
        };

        return RefreshIndicator(
          onRefresh: () async =>
              ref.refresh(groupBillsProvider(widget.groupId).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: kSpace,
                      children: [
                        for (final filter in _BillFilter.values)
                          FilterChip(
                            label: Text(switch (filter) {
                              _BillFilter.open => 'Open',
                              _BillFilter.settled => 'Settled',
                              _BillFilter.all => 'All',
                            }),
                            selected: _filter == filter,
                            onSelected: (_) =>
                                setState(() => _filter = filter),
                          ),
                      ],
                    ),
                    const SizedBox(height: kSpace * 2),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: kSpace * 4,
                        ),
                        child: Text(
                          switch (_filter) {
                            _BillFilter.open => "You're all square here.",
                            _BillFilter.settled => 'Nothing settled yet.',
                            _BillFilter.all => 'No bills.',
                          },
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    else
                      ListGroup(
                        children: [
                          for (final bill in visible)
                            _BillRow(
                              bill: bill,
                              currentUserId: userId,
                              payerName: names[bill.paidBy] ?? 'Someone',
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.bill,
    required this.currentUserId,
    required this.payerName,
  });

  final Bill bill;
  final String currentUserId;
  final String payerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = context.money;
    final share = bill.shareFor(currentUserId);
    final iPaid = bill.paidBy == currentUserId;

    final (statusText, statusColour) = switch (true) {
      _ when bill.isVoid => ('Voided', theme.colorScheme.onSurfaceVariant),
      _ when iPaid && bill.outstanding.isPositive => (
          '${bill.outstanding.format()} owed to you',
          money.owed,
        ),
      _ when iPaid => ('Fully settled', money.owed),
      _ when share == null => ('Not your bill', theme.colorScheme.onSurfaceVariant),
      _ when share.isSettled => ('Settled', money.owed),
      _ when share.isAwaitingConfirmation => ('Awaiting confirmation', money.pending),
      _ => ('You owe ${share.amount.format()}', money.owe),
    };

    final date = DateFormat.MMMd('en_PH').format(bill.billDate);

    return InkWell(
      onTap: () => context.push('/bills/${bill.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      decoration:
                          bill.isVoid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$payerName paid · $date',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StatusLabel(statusText, color: statusColour),
                ],
              ),
            ),
            const SizedBox(width: kSpace * 2),
            AmountText(bill.totalAmount, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
