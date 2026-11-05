import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../groups/domain/group_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../../../settlements/presentation/screens/settle_up_screen.dart';
import '../../domain/bill_models.dart';
import '../bills_controller.dart';

/// The Balances tab (spec §10): who owes whom, per bill.
///
/// Nothing is netted across bills — spec §2 rules out debt simplification, so
/// each bill's debt is listed on its own and settled on its own.
class BalancesTab extends ConsumerWidget {
  const BalancesTab({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bills = ref.watch(groupBillsProvider(groupId));
    final userId = ref.watch(sessionStateProvider).userId ?? '';
    final members = ref.watch(groupMembersProvider(groupId));
    final names = {
      for (final m in members.asData?.value ?? const <GroupMember>[])
        m.userId: m.displayName,
    };

    String nameFor(String id) =>
        id == userId ? 'You' : names[id] ?? 'Someone';

    return bills.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorRetry(
        message: 'Could not load the balances.',
        onRetry: () => ref.invalidate(groupBillsProvider(groupId)),
      ),
      data: (all) {
        // Every open debt in the group, as (debtor, creditor, bill, amount).
        final debts = <({Bill bill, BillShare share})>[
          for (final bill in all)
            if (!bill.isVoid)
              for (final share in bill.shares)
                if (!share.isSettled && share.userId != bill.paidBy)
                  (bill: bill, share: share),
        ];

        if (debts.isEmpty) {
          return const EmptyState(
            icon: Icons.celebration_outlined,
            title: "You're all square!",
            message: 'Nothing outstanding in this group.',
          );
        }

        final byDebtor = <String, List<({Bill bill, BillShare share})>>{};
        for (final debt in debts) {
          byDebtor.putIfAbsent(debt.share.userId, () => []).add(debt);
        }

        // The viewer's own debts first — that is what they came to check.
        final debtors = byDebtor.keys.toList()
          ..sort((a, b) {
            if (a == userId) return -1;
            if (b == userId) return 1;
            return nameFor(a).compareTo(nameFor(b));
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final debtor in debtors) ...[
                    SectionHeader(
                      '${nameFor(debtor)} '
                      '${debtor == userId ? 'owe' : 'owes'}',
                      action: AmountText(
                        Money(
                          byDebtor[debtor]!.fold(
                            0,
                            (t, d) => t + d.share.amount.centavos,
                          ),
                        ),
                        style: theme.textTheme.titleSmall,
                        color: debtor == userId
                            ? context.money.owe
                            : context.money.owed,
                        semanticsPrefix: 'Total',
                      ),
                    ),
                    ListGroup(
                      children: [
                        for (final debt in byDebtor[debtor]!)
                          _DebtRow(
                            bill: debt.bill,
                            share: debt.share,
                            creditorName: nameFor(debt.bill.paidBy),
                            isMine: debtor == userId,
                          ),
                      ],
                    ),
                    if (debtor == userId)
                      for (final entry in _unpaidByCreditor(
                        byDebtor[debtor]!,
                      ).entries)
                        if (entry.value.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: FilledButton.tonalIcon(
                              onPressed: () => SettleUpScreen.showAll(
                                context,
                                items: [
                                  for (final debt in entry.value)
                                    SettleItem(debt.bill, debt.share),
                                ],
                                payerName: nameFor(entry.key),
                              ),
                              icon: const Icon(Icons.done_all, size: 18),
                              label: Text(
                                'Settle all with ${nameFor(entry.key)} · '
                                '${Money(entry.value.fold(0, (t, d) => t + d.share.amount.centavos)).format()}',
                              ),
                            ),
                          ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The caller's unpaid shares — not ones already awaiting confirmation —
/// grouped by who they are owed to, for "Settle all" (DECISIONS D-67).
Map<String, List<({Bill bill, BillShare share})>> _unpaidByCreditor(
  List<({Bill bill, BillShare share})> debts,
) {
  final result = <String, List<({Bill bill, BillShare share})>>{};
  for (final debt in debts) {
    if (debt.share.isUnpaid) {
      result.putIfAbsent(debt.bill.paidBy, () => []).add(debt);
    }
  }
  return result;
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({
    required this.bill,
    required this.share,
    required this.creditorName,
    required this.isMine,
  });

  final Bill bill;
  final BillShare share;
  final String creditorName;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => context.push('/bills/${bill.id}'),
      title: Text(bill.title),
      subtitle: Text(
        share.isAwaitingConfirmation
            ? 'to $creditorName · awaiting confirmation'
            : 'to $creditorName',
        style: theme.textTheme.bodySmall?.copyWith(
          color: share.isAwaitingConfirmation
              ? context.money.pending
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: AmountText(
        share.amount,
        style: theme.textTheme.titleSmall,
        color: isMine ? context.money.owe : context.money.owed,
      ),
    );
  }
}
