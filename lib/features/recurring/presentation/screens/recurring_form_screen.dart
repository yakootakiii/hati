import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/money/money.dart';
import '../../../../core/split/split.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../bills/presentation/bills_controller.dart';
import '../../../groups/domain/group_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../../data/recurring_repository.dart';
import '../../domain/recurring_bill.dart';
import '../recurring_controller.dart';

/// Create or edit a repeating bill (spec §10).
///
/// Deliberately simpler than Add bill: a template cannot be itemized (§5.1),
/// and it has no receipts — those belong to the bills it generates.
class RecurringFormScreen extends ConsumerWidget {
  const RecurringFormScreen({
    required this.groupId,
    this.templateId,
    super.key,
  });

  final String groupId;
  final String? templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionStateProvider).userId;
    final members = ref.watch(groupMembersProvider(groupId));
    final templates = ref.watch(groupRecurringBillsProvider(groupId));

    if (userId == null) return const SizedBox.shrink();

    return members.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(
          message: 'Could not load the group members.',
          onRetry: () => ref.invalidate(groupMembersProvider(groupId)),
        ),
      ),
      data: (list) {
        final existing = templateId == null
            ? null
            : templates.asData?.value
                .where((t) => t.id == templateId)
                .firstOrNull;

        if (templateId != null && existing == null) {
          return Scaffold(
            appBar: AppBar(),
            body: templates.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const EmptyState(
                    icon: Icons.search_off,
                    title: 'Not found',
                    message: 'That repeating bill no longer exists.',
                  ),
          );
        }

        return _Form(
          groupId: groupId,
          currentUserId: userId,
          members: list,
          existing: existing,
        );
      },
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({
    required this.groupId,
    required this.currentUserId,
    required this.members,
    required this.existing,
  });

  final String groupId;
  final String currentUserId;
  final List<GroupMember> members;
  final RecurringBill? existing;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late Money _total = widget.existing?.totalAmount ?? Money.zero;
  late String _paidBy = widget.existing?.paidBy ?? widget.currentUserId;
  late SplitMode _mode = widget.existing?.mode ?? SplitMode.equal;
  late final Set<String> _selected = widget.existing?.participantIds.toSet() ??
      widget.members.map((m) => m.userId).toSet();
  late RecurrenceFrequency _frequency =
      widget.existing?.cadence ?? RecurrenceFrequency.monthly;
  late int _interval = widget.existing?.interval ?? 1;
  late DateTime _nextRun = widget.existing?.nextRunOn ?? DateTime.now();
  late DateTime? _endsOn = widget.existing?.endsOn;
  final Map<String, int> _inputs = {};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  List<GroupMember> get _ordered => canonicalMemberOrder(widget.members);

  RecurringDraft? _draft() {
    final participants = _ordered
        .where((m) => _selected.contains(m.userId))
        .map((m) => SplitParticipant(
              userId: m.userId,
              input: _mode == SplitMode.equal ? null : _inputs[m.userId] ?? 0,
            ))
        .toList(growable: false);

    if (participants.isEmpty) return null;

    return RecurringDraft(
      groupId: widget.groupId,
      title: _title.text.trim(),
      total: _total,
      paidBy: _paidBy,
      mode: _mode,
      participants: participants,
      frequency: _frequency,
      interval: _interval,
      nextRunOn: _nextRun,
      // Monthly keeps to a day of the month; the generator clamps it to the
      // end of a short one (spec §12.7).
      anchorDay:
          _frequency == RecurrenceFrequency.monthly ? _nextRun.day : null,
      endsOn: _endsOn,
    );
  }

  ({SplitResult? result, SplitFailure? failure}) get _preview {
    final draft = _draft();
    if (draft == null) {
      return (result: null, failure: SplitFailure.noParticipants);
    }
    try {
      return (result: SplitEngine.compute(draft.toSplitRequest()), failure: null);
    } on SplitException catch (error) {
      return (result: null, failure: error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(recurringActionsProvider);
    final preview = _preview;
    final canSave = _title.text.trim().isNotEmpty &&
        preview.result != null &&
        !state.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'New repeating bill' : 'Edit repeating bill',
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: kPagePadding,
          child: FilledButton(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: state.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.existing == null ? 'Set it up' : 'Save changes'),
          ),
        ),
      ),
      body: ListView(
        padding: kPagePadding,
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: kSpace * 2),
          ],

          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'What is it for?',
              hintText: 'Rent',
            ),
            onChanged: (_) => setState(() {}),
          ),
          AmountField(
            label: 'Amount each time',
            initial: _total,
            onChanged: (value) => setState(() => _total = value),
          ),
          const SizedBox(height: kSpace * 2),

          DropdownButtonFormField<String>(
            initialValue: _paidBy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid by'),
            items: [
              for (final member in _ordered)
                DropdownMenuItem(
                  value: member.userId,
                  child: Text(
                    member.userId == widget.currentUserId
                        ? 'Me'
                        : member.displayName,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _paidBy = value);
            },
          ),

          const Divider(height: kSpace * 5),
          Text('How often', style: theme.textTheme.titleMedium),
          const SizedBox(height: kSpace * 1.5),

          SegmentedButton<RecurrenceFrequency>(
            segments: const [
              ButtonSegment(
                value: RecurrenceFrequency.weekly,
                label: Text('Weekly'),
              ),
              ButtonSegment(
                value: RecurrenceFrequency.monthly,
                label: Text('Monthly'),
              ),
              ButtonSegment(
                value: RecurrenceFrequency.yearly,
                label: Text('Yearly'),
              ),
            ],
            selected: {_frequency},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _frequency = selection.first),
          ),
          const SizedBox(height: kSpace * 2),

          // Stacked rather than side by side: at phone width the two fields
          // together overflow, and at 200% text they have no chance.
          DropdownButtonFormField<int>(
            initialValue: _interval,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Every'),
            items: [
              for (var i = 1; i <= 12; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    i == 1
                        ? '1 ${_unit(_frequency)}'
                        : '$i ${_unit(_frequency)}s',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _interval = value);
            },
          ),
          const SizedBox(height: kSpace * 2),
          _DateField(
            label: 'Starting',
            date: _nextRun,
            onChanged: (value) => setState(() => _nextRun = value),
          ),

          if (_frequency == RecurrenceFrequency.monthly) ...[
            const SizedBox(height: kSpace),
            Text(
              'Runs on the ${_nextRun.day}${_ordinal(_nextRun.day)} each month. '
              'In a shorter month it moves to the last day.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: kSpace * 2),
          _DateField(
            label: 'Ends on',
            date: _endsOn,
            optional: true,
            onChanged: (value) => setState(() => _endsOn = value),
            onCleared: () => setState(() => _endsOn = null),
          ),

          const Divider(height: kSpace * 5),
          Text('Split', style: theme.textTheme.titleMedium),
          const SizedBox(height: kSpace * 1.5),

          // No Items segment: a template cannot be itemized (spec §5.1).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<SplitMode>(
              segments: const [
                ButtonSegment(value: SplitMode.equal, label: Text('Equal')),
                ButtonSegment(value: SplitMode.exact, label: Text('Exact')),
                ButtonSegment(value: SplitMode.percent, label: Text('%')),
                ButtonSegment(value: SplitMode.shares, label: Text('Shares')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() {
                _mode = selection.first;
                _inputs.clear();
              }),
            ),
          ),

          for (final member in _ordered)
            CheckboxListTile(
              value: _selected.contains(member.userId),
              onChanged: (_) => setState(() {
                if (!_selected.remove(member.userId)) {
                  _selected.add(member.userId);
                }
                _inputs.remove(member.userId);
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(member.displayName),
              subtitle: preview.result == null
                  ? null
                  : Text(preview.result!.amountFor(member.userId).format()),
              secondary: _selected.contains(member.userId) &&
                      _mode != SplitMode.equal
                  ? SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.end,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: _mode == SplitMode.exact ? '₱' : null,
                          suffixText: switch (_mode) {
                            SplitMode.percent => '%',
                            SplitMode.shares => '×',
                            _ => null,
                          },
                        ),
                        onChanged: (text) => setState(() {
                          final parsed = Money.tryParse(text)?.centavos;
                          if (parsed == null) {
                            _inputs.remove(member.userId);
                          } else {
                            _inputs[member.userId] =
                                _mode == SplitMode.shares ? parsed * 10 : parsed;
                          }
                        }),
                      ),
                    )
                  : null,
            ),

          if (preview.failure != null)
            Padding(
              padding: const EdgeInsets.only(top: kSpace),
              child: Text(
                _failureCopy(preview.failure!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),

          const SizedBox(height: kSpace * 4),
        ],
      ),
    );
  }

  static String _unit(RecurrenceFrequency frequency) => switch (frequency) {
        RecurrenceFrequency.weekly => 'week',
        RecurrenceFrequency.monthly => 'month',
        RecurrenceFrequency.yearly => 'year',
      };

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return 'th';
    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }

  static String _failureCopy(SplitFailure failure) => switch (failure) {
        SplitFailure.noParticipants => 'Pick at least one person.',
        SplitFailure.invalidTotal => 'Enter the amount first.',
        SplitFailure.exactSumMismatch =>
          "The amounts don't add up to the total.",
        SplitFailure.percentSumMismatch =>
          'The percentages must add up to 100%.',
        SplitFailure.nonPositiveWeight =>
          'Every share has to be more than zero.',
        _ => 'Check the split.',
      };

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;

    final actions = ref.read(recurringActionsProvider.notifier);
    final existing = widget.existing;

    final ok = existing == null
        ? await actions.create(draft) != null
        : await actions.edit(existing.id, draft);

    if (!mounted) return;
    if (ok) {
      // Opened from a deep link there is nothing behind this screen, so fall
      // back to the list rather than dead-ending on "nothing to pop".
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.recurring(widget.groupId));
      }
    } else {
      setState(() => _error = actions.lastError);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onChanged,
    this.optional = false,
    this.onCleared,
  });

  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onChanged;
  final bool optional;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final shown = date;

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: shown ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: optional && shown != null
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: onCleared,
                  icon: const Icon(Icons.close, size: 18),
                )
              : null,
        ),
        child: Text(
          shown == null ? 'Never' : DateFormat.yMMMd('en_PH').format(shown),
        ),
      ),
    );
  }
}
