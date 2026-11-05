import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/split/split.dart';
import '../../groups/domain/group_models.dart';
import '../data/bills_repository.dart';
import '../domain/bill_models.dart';
import 'bills_controller.dart';

part 'bill_form_controller.freezed.dart';
part 'bill_form_controller.g.dart';

/// One editable line on an itemized bill.
@freezed
abstract class ItemDraft with _$ItemDraft {
  const factory ItemDraft({
    required String key,
    @Default('') String name,
    @Default(Money.zero) Money amount,
    @Default(<String>{}) Set<String> assignees,
  }) = _ItemDraft;
}

@freezed
abstract class BillFormState with _$BillFormState {
  const factory BillFormState({
    required String groupId,
    required String paidBy,
    required DateTime billDate,
    @Default('') String title,
    @Default(Money.zero) Money enteredTotal,
    @Default(SplitMode.equal) SplitMode mode,
    @Default(<String>{}) Set<String> selected,
    @Default(<String, int>{}) Map<String, int> inputs,
    @Default(<ItemDraft>[]) List<ItemDraft> items,
    @Default(Money.zero) Money serviceCharge,
    @Default(Money.zero) Money tax,
    @Default(Money.zero) Money discount,
    String? notes,
    String? category,
    String? editingBillId,
  }) = _BillFormState;

  const BillFormState._();

  /// In itemized mode the total is derived, never typed — the items and extras
  /// decide it, so the "items must add up to the total" failure cannot happen
  /// through the UI at all (DECISIONS D-32).
  Money get total => mode == SplitMode.itemized
      ? Money(
          items.fold<int>(0, (t, i) => t + i.amount.centavos) +
              serviceCharge.centavos +
              tax.centavos -
              discount.centavos,
        )
      : enteredTotal;

  bool get isEditing => editingBillId != null;
}

/// Drives the Add / Edit bill screen.
@riverpod
class BillForm extends _$BillForm {
  @override
  BillFormState build({
    required String groupId,
    required String currentUserId,
  }) {
    return BillFormState(
      groupId: groupId,
      paidBy: currentUserId,
      billDate: DateTime.now(),
    );
  }

  /// Loads an existing bill for editing.
  void loadFrom(Bill bill) {
    state = BillFormState(
      groupId: bill.groupId,
      paidBy: bill.paidBy,
      billDate: bill.billDate,
      title: bill.title,
      enteredTotal: bill.totalAmount,
      mode: bill.mode,
      selected: {for (final s in bill.shares) s.userId},
      inputs: {
        for (final s in bill.shares)
          if (_inputFor(bill, s) != null) s.userId: _inputFor(bill, s)!,
      },
      items: [
        for (var i = 0; i < bill.items.length; i++)
          ItemDraft(
            key: 'existing-$i',
            name: bill.items[i].name,
            amount: bill.items[i].amount,
            assignees: bill.items[i].assignees.toSet(),
          ),
      ],
      serviceCharge: Money(bill.extras.serviceCharge),
      tax: Money(bill.extras.tax),
      discount: Money(bill.extras.discount),
      notes: bill.notes,
      category: bill.category,
      editingBillId: bill.id,
    );
  }

  /// The stored amount is the share for exact mode; percent and shares keep
  /// their raw input on `bill_shares.split_input`.
  static int? _inputFor(Bill bill, BillShare share) => switch (bill.mode) {
        SplitMode.exact => share.amount.centavos,
        _ => null,
      };

  void setTitle(String value) => state = state.copyWith(title: value);
  void setNotes(String? value) => state = state.copyWith(notes: value);
  void setCategory(String? value) => state = state.copyWith(category: value);
  void setDate(DateTime value) => state = state.copyWith(billDate: value);
  void setPaidBy(String userId) => state = state.copyWith(paidBy: userId);
  void setTotal(Money value) => state = state.copyWith(enteredTotal: value);
  void setServiceCharge(Money value) =>
      state = state.copyWith(serviceCharge: value);
  void setTax(Money value) => state = state.copyWith(tax: value);
  void setDiscount(Money value) => state = state.copyWith(discount: value);

  /// Switching mode clears the per-person inputs, which mean different things
  /// in each mode and would otherwise be read as the wrong unit.
  void setMode(SplitMode mode) =>
      state = state.copyWith(mode: mode, inputs: const {});

  void toggleParticipant(String userId) {
    final selected = {...state.selected};
    if (!selected.remove(userId)) selected.add(userId);

    final inputs = {...state.inputs}..remove(userId);
    state = state.copyWith(selected: selected, inputs: inputs);
  }

  void selectAll(Iterable<String> userIds) =>
      state = state.copyWith(selected: userIds.toSet());

  void setInput(String userId, int? value) {
    final inputs = {...state.inputs};
    if (value == null) {
      inputs.remove(userId);
    } else {
      inputs[userId] = value;
    }
    state = state.copyWith(inputs: inputs);
  }

  void addItem() => state = state.copyWith(
        items: [
          ...state.items,
          ItemDraft(key: 'item-${DateTime.now().microsecondsSinceEpoch}'),
        ],
      );

  void updateItem(String key, ItemDraft Function(ItemDraft) change) =>
      state = state.copyWith(
        items: [
          for (final item in state.items)
            if (item.key == key) change(item) else item,
        ],
      );

  void removeItem(String key) => state = state.copyWith(
        items: [
          for (final item in state.items)
            if (item.key != key) item,
        ],
      );
}

/// The live preview: what each person would owe if the bill were saved now.
///
/// Runs the same [SplitEngine] the server runs, over the same canonically
/// ordered participants, so the numbers on screen are the numbers that will be
/// stored (spec §4.1 — the client previews, the server decides).
({SplitResult? result, SplitFailure? failure}) previewSplit(
  BillFormState form,
  List<GroupMember> members,
) {
  final draft = buildDraft(form, members);
  if (draft == null) {
    return (result: null, failure: SplitFailure.noParticipants);
  }
  try {
    return (result: SplitEngine.compute(draft.toSplitRequest()), failure: null);
  } on SplitException catch (error) {
    return (result: null, failure: error.failure);
  }
}

/// Assembles the payload, or null when nothing is selected yet.
BillDraft? buildDraft(BillFormState form, List<GroupMember> members) {
  final ordered = canonicalMemberOrder(members)
      .where((m) => form.selected.contains(m.userId))
      .toList(growable: false);
  if (ordered.isEmpty) return null;

  return BillDraft(
    groupId: form.groupId,
    title: form.title.trim(),
    total: form.total,
    paidBy: form.paidBy,
    mode: form.mode,
    billDate: form.billDate,
    notes: form.notes,
    category: form.category,
    participants: [
      for (final member in ordered)
        SplitParticipant(
          userId: member.userId,
          input: switch (form.mode) {
            SplitMode.equal || SplitMode.itemized => null,
            _ => form.inputs[member.userId] ?? 0,
          },
        ),
    ],
    items: [
      for (final item in form.items)
        SplitItem(
          name: item.name,
          amount: item.amount,
          assignees: item.assignees.toList(growable: false),
        ),
    ],
    extras: ItemizedExtras(
      serviceCharge: form.serviceCharge,
      tax: form.tax,
      discount: form.discount,
    ),
  );
}

/// What is still unassigned, for the "₱X left to assign" hint (spec §10).
///
/// Returns null for modes where nothing is assigned by hand.
({int remaining, String label})? assignmentRemainder(BillFormState form) {
  switch (form.mode) {
    case SplitMode.exact:
      final assigned = form.selected.fold<int>(
        0,
        (total, id) => total + (form.inputs[id] ?? 0),
      );
      final remaining = form.total.centavos - assigned;
      return (
        remaining: remaining,
        label: remaining == 0
            ? 'All assigned'
            : remaining > 0
                ? '${Money(remaining).format()} left to assign'
                : '${Money(-remaining).format()} over',
      );

    case SplitMode.percent:
      final assigned = form.selected.fold<int>(
        0,
        (total, id) => total + (form.inputs[id] ?? 0),
      );
      final remaining = 10000 - assigned;
      final formatted = (remaining.abs() / 100).toStringAsFixed(2);
      return (
        remaining: remaining,
        label: remaining == 0
            ? 'Adds up to 100%'
            : remaining > 0
                ? '$formatted% left'
                : '$formatted% over',
      );

    case SplitMode.equal || SplitMode.shares || SplitMode.itemized:
      return null;
  }
}
