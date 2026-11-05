import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../groups/domain/group_models.dart';
import '../bill_form_controller.dart';
import '../bills_controller.dart';

/// The itemized editor (spec §10): item rows with assignee chips, the three
/// extras, and a per-person breakdown.
///
/// The bill total is derived here rather than typed, so "the items must add up
/// to the total" cannot be reached through the UI (DECISIONS D-32).
class ItemizedEditor extends ConsumerWidget {
  const ItemizedEditor({
    required this.groupId,
    required this.currentUserId,
    required this.members,
    super.key,
  });

  final String groupId;
  final String currentUserId;
  final List<GroupMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final form = ref.watch(
      billFormProvider(groupId: groupId, currentUserId: currentUserId),
    );
    final controller = ref.read(
      billFormProvider(groupId: groupId, currentUserId: currentUserId).notifier,
    );
    final ordered = canonicalMemberOrder(members);
    final preview = previewSplit(form, members);

    final subtotal = Money(
      form.items.fold<int>(0, (t, i) => t + i.amount.centavos),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: kSpace),

        if (form.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpace * 2),
            child: Text(
              'No items yet. Add the first line from the receipt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        for (final item in form.items)
          _ItemRow(
            key: ValueKey(item.key),
            item: item,
            members: ordered,
            onChanged: (change) => controller.updateItem(item.key, change),
            onRemove: () => controller.removeItem(item.key),
          ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: controller.addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),

        const Divider(height: kSpace * 4),
        Text('Charges and discounts', style: theme.textTheme.titleMedium),
        const SizedBox(height: kSpace * 1.5),

        Row(
          children: [
            Expanded(
              child: AmountField(
                label: 'Service charge',
                initial: form.serviceCharge,
                onChanged: controller.setServiceCharge,
              ),
            ),
            const SizedBox(width: kSpace * 1.5),
            Expanded(
              child: AmountField(
                label: 'Tax',
                initial: form.tax,
                onChanged: controller.setTax,
              ),
            ),
          ],
        ),
        const SizedBox(height: kSpace * 2),
        AmountField(
          label: 'Discount',
          initial: form.discount,
          onChanged: controller.setDiscount,
        ),

        const Divider(height: kSpace * 4),
        _BreakdownRow(label: 'Subtotal', amount: subtotal),
        if (form.serviceCharge.isPositive)
          _BreakdownRow(label: 'Service charge', amount: form.serviceCharge),
        if (form.tax.isPositive) _BreakdownRow(label: 'Tax', amount: form.tax),
        if (form.discount.isPositive)
          _BreakdownRow(
            label: 'Discount',
            amount: form.discount.negated,
          ),
        const SizedBox(height: kSpace),
        _BreakdownRow(label: 'Total', amount: form.total, emphasised: true),

        if (preview.result != null) ...[
          const Divider(height: kSpace * 4),
          Text('Per person', style: theme.textTheme.titleMedium),
          const SizedBox(height: kSpace),
          for (final member in ordered)
            if (preview.result!.amountFor(member.userId).isPositive ||
                form.selected.contains(member.userId))
              _BreakdownRow(
                label: member.displayName,
                amount: preview.result!.amountFor(member.userId),
              ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.item,
    required this.members,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final ItemDraft item;
  final List<GroupMember> members;
  final ValueChanged<ItemDraft Function(ItemDraft)> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _name =
      TextEditingController(text: widget.item.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: const EdgeInsets.only(bottom: kSpace * 1.5),
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        widget.onChanged((item) => item.copyWith(name: value)),
                  ),
                ),
                const SizedBox(width: kSpace * 1.5),
                Expanded(
                  flex: 2,
                  child: AmountField(
                    label: 'Price',
                    initial: widget.item.amount,
                    onChanged: (value) => widget
                        .onChanged((item) => item.copyWith(amount: value)),
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove item',
                ),
              ],
            ),
            const SizedBox(height: kSpace),
            Wrap(
              spacing: kSpace,
              children: [
                for (final member in widget.members)
                  FilterChip(
                    label: Text(member.displayName),
                    selected: widget.item.assignees.contains(member.userId),
                    onSelected: (selected) => widget.onChanged((item) {
                      final assignees = {...item.assignees};
                      if (selected) {
                        assignees.add(member.userId);
                      } else {
                        assignees.remove(member.userId);
                      }
                      return item.copyWith(assignees: assignees);
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    this.emphasised = false,
  });

  final String label;
  final Money amount;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasised
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          AmountText(amount, style: style),
        ],
      ),
    );
  }
}
