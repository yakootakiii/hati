import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/money/money.dart';
import '../../../../core/push/push_prompt.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';
import '../../domain/bill_models.dart';
import '../bills_controller.dart';

/// Home (spec §10): what you owe, what you are owed, and what needs doing.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(myBalancesProvider);
    final openShares = ref.watch(myOpenSharesProvider);

    return Scaffold(
      appBar: AppBar(
        // On wide screens the navigation rail already carries the mark.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.sizeOf(context).width < 840) ...[
              const BrandMark(size: 22),
              const SizedBox(width: 10),
            ],
            const Text('Hati'),
          ],
        ),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: CircleAvatar(
              radius: 15,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Icon(
                Icons.person_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: kSpace),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myBalancesProvider)
            ..invalidate(myOpenSharesProvider);
          await ref.read(myBalancesProvider.future);
        },
        child: balances.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorRetry(
            message: 'Could not load your balances.',
            onRetry: () => ref.invalidate(myBalancesProvider),
          ),
          data: (groups) {
            final owed = Money(
              groups.fold(0, (t, g) => t + g.owedToMe.centavos),
            );
            final owing = Money(
              groups.fold(0, (t, g) => t + g.owedByMe.centavos),
            );
            final shares = openShares.asData?.value ?? const <OpenShare>[];

            if (groups.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: kSpace * 8),
                  EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Nothing here yet',
                    message:
                        'Make a group, invite your barkada, and add your first '
                        'shared bill.',
                    actionLabel: 'Go to groups',
                    onAction: () => context.go('/groups'),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Web only: turning on notifications (D-72).
                      const PushPrompt(),
                      _BalanceHeader(owing: owing, owed: owed),

                      if (shares.isNotEmpty) ...[
                        const SectionHeader('Needs your attention'),
                        ListGroup(
                          dividerIndent: 68,
                          children: [
                            for (final share in shares)
                              _OpenShareRow(share: share),
                          ],
                        ),
                      ],

                      const SectionHeader('By group'),
                      ListGroup(
                        children: [
                          for (final group in groups)
                            _GroupBalanceRow(balance: group),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Where you stand: what you owe and what you are owed, side by side.
///
/// Deliberately not a net figure — Hati never offsets one debt against
/// another (spec §2), so a net number would invite paying the wrong amount.
class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.owing, required this.owed});

  final Money owing;
  final Money owed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = context.money;
    final square = owing.isZero && owed.isZero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: kSpace * 1.5),
        if (square) ...[
          Text("You're all square!", style: theme.textTheme.headlineSmall),
          const SizedBox(height: kSpace / 2),
          Text(
            'Nothing to settle anywhere. Enjoy it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpace * 2),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(kRadiusLg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Side(
                    label: 'You owe',
                    amount: owing,
                    colour: money.owe,
                    icon: Icons.north_east,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _Side(
                    label: "You're owed",
                    amount: owed,
                    colour: money.owed,
                    icon: Icons.south_west,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.amount,
    required this.colour,
    required this.icon,
  });

  final String label;
  final Money amount;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon plus label, so the direction never rests on colour
              // alone (spec §11).
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpace),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(
              amount,
              style: theme.textTheme.headlineSmall,
              color:
                  amount.isZero ? theme.colorScheme.onSurfaceVariant : colour,
              semanticsPrefix: label,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenShareRow extends StatelessWidget {
  const _OpenShareRow({required this.share});

  final OpenShare share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => context.push('/bills/${share.billId}'),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: share.isAwaitingConfirmation
              ? context.money.pendingContainer
              : context.money.oweContainer,
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        child: Icon(
          share.isAwaitingConfirmation
              ? Icons.schedule
              : Icons.payments_outlined,
          size: 18,
          color: share.isAwaitingConfirmation
              ? context.money.pending
              : context.money.owe,
        ),
      ),
      title: Text(share.billTitle),
      subtitle: Text(
        share.isAwaitingConfirmation
            ? '${share.groupName} · waiting on ${share.payerName}'
            : '${share.groupName} · pay ${share.payerName}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: AmountText(
        share.amount,
        style: theme.textTheme.titleSmall,
        color: share.isAwaitingConfirmation
            ? context.money.pending
            : context.money.owe,
      ),
    );
  }
}

class _GroupBalanceRow extends StatelessWidget {
  const _GroupBalanceRow({required this.balance});

  final GroupBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = balance.net;

    final (label, colour) = switch (true) {
      _ when balance.isSquare => ('All square', theme.colorScheme.onSurfaceVariant),
      _ when net.isPositive => ('owed to you', context.money.owed),
      _ when net.isNegative => ('you owe', context.money.owe),
      _ => ('balanced out', theme.colorScheme.onSurfaceVariant),
    };

    return ListTile(
      onTap: () => context.push('/groups/${balance.groupId}'),
      title: Text(balance.groupName),
      subtitle: balance.isSquare
          ? Text(label, style: theme.textTheme.bodySmall)
          : Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!balance.isSquare)
            AmountText(
              net.abs,
              style: theme.textTheme.titleSmall,
              color: colour,
            ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
