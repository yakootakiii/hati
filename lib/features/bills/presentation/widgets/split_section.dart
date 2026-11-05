import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/money/money.dart';
import '../../../../core/split/split.dart';
import '../../../groups/domain/group_models.dart';
import '../bill_form_controller.dart';
import '../bills_controller.dart';

/// The Split section of the Add/Edit bill screen (spec §10).
///
/// Mode switch, participant checklist with per-mode inputs, the live
/// "remaining" hint, and a preview of what each person ends up owing.
class SplitSection extends ConsumerWidget {
  const SplitSection({
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
    final args = (groupId: groupId, currentUserId: currentUserId);
    final form = ref.watch(billFormProvider(
      groupId: args.groupId,
      currentUserId: args.currentUserId,
    ));
    final controller = ref.read(billFormProvider(
      groupId: args.groupId,
      currentUserId: args.currentUserId,
    ).notifier);

    final ordered = canonicalMemberOrder(members);
    final preview = previewSplit(form, members);
    final remainder = assignmentRemainder(form);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Split', style: theme.textTheme.titleMedium),
        const SizedBox(height: kSpace * 1.5),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<SplitMode>(
            segments: const [
              ButtonSegment(value: SplitMode.equal, label: Text('Equal')),
              ButtonSegment(value: SplitMode.exact, label: Text('Exact')),
              ButtonSegment(value: SplitMode.percent, label: Text('%')),
              ButtonSegment(value: SplitMode.shares, label: Text('Shares')),
              ButtonSegment(value: SplitMode.itemized, label: Text('Items')),
            ],
            selected: {form.mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                controller.setMode(selection.first),
          ),
        ),

        if (form.mode != SplitMode.itemized) ...[
          const SizedBox(height: kSpace * 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${form.selected.length} of ${ordered.length} selected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => controller.selectAll(
                  form.selected.length == ordered.length
                      ? const <String>[]
                      : ordered.map((m) => m.userId),
                ),
                child: Text(
                  form.selected.length == ordered.length
                      ? 'Clear all'
                      : 'Select all',
                ),
              ),
            ],
          ),
          for (final member in ordered)
            _ParticipantRow(
              member: member,
              form: form,
              controller: controller,
              amount: preview.result?.amountFor(member.userId),
            ),
        ],

        if (remainder != null) ...[
          const SizedBox(height: kSpace),
          _RemainingHint(
            label: remainder.label,
            isBalanced: remainder.remaining == 0,
          ),
        ],

        const SizedBox(height: kSpace * 2),
        _PreviewSummary(
          failure: preview.failure,
          result: preview.result,
          hasSelection: form.selected.isNotEmpty,
          mode: form.mode,
        ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.member,
    required this.form,
    required this.controller,
    required this.amount,
  });

  final GroupMember member;
  final BillFormState form;
  final BillForm controller;
  final Money? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = form.selected.contains(member.userId);

    return Semantics(
      label: '${member.displayName}'
          '${selected && amount != null ? ', owes ${amount!.format()}' : ''}',
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) => controller.toggleParticipant(member.userId),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(member.displayName),
        subtitle: selected && amount != null
            ? Text(
                amount!.format(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        secondary: selected && form.mode != SplitMode.equal
            ? SizedBox(
                width: 108,
                child: _InputField(
                  mode: form.mode,
                  value: form.inputs[member.userId],
                  onChanged: (value) =>
                      controller.setInput(member.userId, value),
                ),
              )
            : null,
      ),
    );
  }
}

/// The per-mode number next to each participant.
///
/// Each mode stores an integer in its own unit — centavos, hundredths of a
/// percent, thousandths of a share — so nothing is ever parsed into a double.
class _InputField extends StatefulWidget {
  const _InputField({
    required this.mode,
    required this.value,
    required this.onChanged,
  });

  final SplitMode mode;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));

  String _format(int? value) {
    if (value == null) return '';
    return switch (widget.mode) {
      SplitMode.exact => Money(value).formatBare(),
      SplitMode.percent => (value / 100).toStringAsFixed(2),
      SplitMode.shares => (value / 1000).toStringAsFixed(
          value % 1000 == 0 ? 0 : 1,
        ),
      _ => '',
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.end,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        isDense: true,
        prefixText: widget.mode == SplitMode.exact ? '₱' : null,
        suffixText: switch (widget.mode) {
          SplitMode.percent => '%',
          SplitMode.shares => '×',
          _ => null,
        },
      ),
      onChanged: (text) {
        if (text.trim().isEmpty) {
          widget.onChanged(null);
          return;
        }
        final parsed = switch (widget.mode) {
          // Percent keeps two decimals and shares three, both parsed through
          // Money's exact centavo parser and then rescaled.
          SplitMode.exact => Money.tryParse(text)?.centavos,
          SplitMode.percent => Money.tryParse(text)?.centavos,
          SplitMode.shares => _parseShares(text),
          _ => null,
        };
        widget.onChanged(parsed);
      },
    );
  }

  /// Shares arrive as thousandths, so 0.5 becomes 500.
  static int? _parseShares(String text) {
    final asHundredths = Money.tryParse(text)?.centavos;
    return asHundredths == null ? null : asHundredths * 10;
  }
}

class _RemainingHint extends StatelessWidget {
  const _RemainingHint({required this.label, required this.isBalanced});

  final String label;
  final bool isBalanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour =
        isBalanced ? theme.colorScheme.tertiary : theme.colorScheme.error;

    return Row(
      children: [
        // Paired with an icon so the state never rests on colour alone
        // (spec §11).
        Icon(
          isBalanced ? Icons.check_circle_outline : Icons.info_outline,
          size: 18,
          color: colour,
        ),
        const SizedBox(width: kSpace),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({
    required this.failure,
    required this.result,
    required this.hasSelection,
    required this.mode,
  });

  final SplitFailure? failure;
  final SplitResult? result;
  final bool hasSelection;
  final SplitMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hasSelection) {
      return Text(
        mode == SplitMode.itemized
            ? 'Add items below and tick who shares each one.'
            : 'Pick who is splitting this bill.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (failure != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: kSpace),
          Expanded(
            child: Text(
              splitFailureCopy(failure!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 18,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(width: kSpace),
        Expanded(
          child: Text(
            'Adds up to ${result!.total.format()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline copy for a split that does not yet work, shown against the Split
/// section rather than as a page-level error.
String splitFailureCopy(SplitFailure failure) => switch (failure) {
      SplitFailure.noParticipants => 'Pick at least one person.',
      SplitFailure.duplicateParticipant => 'Someone is listed twice.',
      SplitFailure.invalidTotal => 'Enter the bill amount first.',
      SplitFailure.exactSumMismatch => "The amounts don't add up to the total.",
      SplitFailure.percentSumMismatch => 'The percentages must add up to 100%.',
      SplitFailure.nonPositiveWeight => 'Every share has to be more than zero.',
      SplitFailure.itemWithoutAssignees =>
        'Every item needs at least one person on it.',
      SplitFailure.unknownAssignee =>
        'An item is assigned to someone not on this bill.',
      SplitFailure.itemsTotalMismatch =>
        "The items and extras don't add up to the total.",
      SplitFailure.negativeShare =>
        'That discount leaves someone owing less than nothing.',
    };
