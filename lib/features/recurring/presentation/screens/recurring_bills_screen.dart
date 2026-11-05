import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../groups/domain/group_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../../domain/recurring_bill.dart';
import '../recurring_controller.dart';

/// Recurring bills for one group (spec §10).
class RecurringBillsScreen extends ConsumerWidget {
  const RecurringBillsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(groupRecurringBillsProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));
    final names = {
      for (final m in members.asData?.value ?? const <GroupMember>[])
        m.userId: m.displayName,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Repeating bills')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addRecurring(groupId)),
        icon: const Icon(Icons.add),
        label: const Text('New repeating bill'),
      ),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load the repeating bills.',
          onRetry: () => ref.invalidate(groupRecurringBillsProvider(groupId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.repeat,
              title: 'Nothing repeating yet',
              message:
                  'Set up rent, wifi or a subscription once and Hati will add '
                  'it for you each time.',
              actionLabel: 'New repeating bill',
              actionIcon: Icons.add,
              onAction: () => context.push(Routes.addRecurring(groupId)),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final template in list)
                _TemplateCard(
                  template: template,
                  payerName: names[template.paidBy] ?? 'Someone',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({required this.template, required this.payerName});

  final RecurringBill template;
  final String payerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card.filled(
      margin: const EdgeInsets.only(bottom: kSpace * 1.5),
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                AmountText(
                  template.totalAmount,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: kSpace / 2),
            Text(
              '${template.scheduleLabel} · $payerName pays',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace),

            // Paused is spelled out, never carried by a dimmed card alone
            // (spec §11).
            Row(
              children: [
                Icon(
                  template.paused ? Icons.pause_circle_outline : Icons.event,
                  size: 16,
                  color: template.paused
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: kSpace / 2),
                Expanded(
                  child: Text(
                    template.paused
                        ? 'Paused'
                        : 'Next on ${DateFormat.yMMMd('en_PH').format(template.nextRunOn)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _togglePause(context, ref),
                  child: Text(template.paused ? 'Resume' : 'Pause'),
                ),
                IconButton(
                  tooltip: 'Edit ${template.title}',
                  onPressed: () => context.push(
                    Routes.editRecurring(template.groupId, template.id),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete ${template.title}',
                  onPressed: () => _confirmDelete(context, ref),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePause(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(recurringActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await actions.setPaused(
      templateId: template.id,
      groupId: template.groupId,
      paused: !template.paused,
    );

    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'That did not work.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(recurringActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${template.title}?'),
        content: const Text(
          'It stops repeating. The bills it already made stay exactly as they '
          'are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await actions.remove(
      templateId: template.id,
      groupId: template.groupId,
    );
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'Could not delete it.')),
      );
    }
  }
}
