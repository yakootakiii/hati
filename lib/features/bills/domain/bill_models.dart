import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/split/split.dart';

part 'bill_models.freezed.dart';
part 'bill_models.g.dart';

/// One participant's share of a bill.
@freezed
abstract class BillShare with _$BillShare {
  const factory BillShare({
    required String id,
    required String userId,
    @MoneyConverter() required Money amount,
    required String status,
    DateTime? settledAt,
    DateTime? lastRemindedAt,
  }) = _BillShare;

  const BillShare._();

  factory BillShare.fromJson(Map<String, dynamic> json) =>
      _$BillShareFromJson(json);

  bool get isSettled => status == 'settled';
  bool get isAwaitingConfirmation => status == 'pending_confirmation';
  bool get isUnpaid => status == 'unpaid';

  /// Spec §11: status is never carried by colour alone.
  String get statusLabel => switch (status) {
        'settled' => 'Settled',
        'pending_confirmation' => 'Awaiting confirmation',
        _ => 'Unpaid',
      };
}

/// A line on an itemized bill.
@freezed
abstract class BillItemRow with _$BillItemRow {
  const factory BillItemRow({
    required String id,
    required String name,
    @MoneyConverter() required Money amount,
    @Default(<String>[]) List<String> assignees,
    int? position,
  }) = _BillItemRow;

  factory BillItemRow.fromJson(Map<String, dynamic> json) =>
      _$BillItemRowFromJson(json);
}

@freezed
abstract class BillAttachment with _$BillAttachment {
  const factory BillAttachment({
    required String id,
    required String path,
    String? uploadedBy,
  }) = _BillAttachment;

  factory BillAttachment.fromJson(Map<String, dynamic> json) =>
      _$BillAttachmentFromJson(json);
}

/// A bill with everything the list and the detail screen need.
@freezed
abstract class Bill with _$Bill {
  const factory Bill({
    required String id,
    required String groupId,
    required String title,
    @MoneyConverter() required Money totalAmount,
    required String paidBy,
    required String createdBy,
    required String splitMode,
    required DateTime billDate,
    required String status,
    String? notes,
    String? category,
    /// Where the payer asked to be paid: one of their payment methods, or
    /// null for any of them.
    String? receiveMethodId,
    @Default(<BillShare>[]) List<BillShare> shares,
    @Default(<BillItemRow>[]) List<BillItemRow> items,
    @Default(<BillAttachment>[]) List<BillAttachment> attachments,
    @Default(ItemizedExtrasJson()) ItemizedExtrasJson extras,
    DateTime? createdAt,
  }) = _Bill;

  const Bill._();

  factory Bill.fromJson(Map<String, dynamic> json) => _$BillFromJson(json);

  bool get isVoid => status == 'void';
  bool get isSettled => status == 'settled';

  SplitMode get mode => SplitMode.fromJson(splitMode);

  /// What is still owed on this bill, ignoring the payer's own share.
  Money get outstanding => Money(
        shares
            .where((s) => !s.isSettled && s.userId != paidBy)
            .fold(0, (total, s) => total + s.amount.centavos),
      );

  BillShare? shareFor(String userId) =>
      shares.where((s) => s.userId == userId).firstOrNull;

  /// The viewer owes something on this bill and has not settled it.
  bool owedBy(String userId) {
    final share = shareFor(userId);
    return !isVoid && share != null && !share.isSettled && userId != paidBy;
  }

  /// Whoever added the bill, or its payer, may edit — and only while no money
  /// is in flight (spec §12.1). The server is the authority; this is the UI's
  /// copy of the rule so the button can be hidden rather than fail on tap.
  bool canEdit(String userId) =>
      !isVoid &&
      (userId == createdBy || userId == paidBy) &&
      shares.every((s) => !s.isAwaitingConfirmation) &&
      shares.where((s) => s.userId != paidBy).every((s) => !s.isSettled);
}

/// `bills.itemized_extras` (DECISIONS D-02).
@freezed
abstract class ItemizedExtrasJson with _$ItemizedExtrasJson {
  const factory ItemizedExtrasJson({
    @Default(0) int serviceCharge,
    @Default(0) int tax,
    @Default(0) int discount,
  }) = _ItemizedExtrasJson;

  const ItemizedExtrasJson._();

  factory ItemizedExtrasJson.fromJson(Map<String, dynamic> json) =>
      _$ItemizedExtrasJsonFromJson(json);

  ItemizedExtras toDomain() => ItemizedExtras(
        serviceCharge: Money(serviceCharge),
        tax: Money(tax),
        discount: Money(discount),
      );

  bool get isEmpty => serviceCharge == 0 && tax == 0 && discount == 0;
}

/// What the caller owes and is owed in one group (spec §7 `get_my_balances`).
@freezed
abstract class GroupBalance with _$GroupBalance {
  const factory GroupBalance({
    required String groupId,
    required String groupName,
    @MoneyConverter() required Money owedByMe,
    @MoneyConverter() required Money owedToMe,
  }) = _GroupBalance;

  const GroupBalance._();

  factory GroupBalance.fromJson(Map<String, dynamic> json) =>
      _$GroupBalanceFromJson(json);

  bool get isSquare => owedByMe.isZero && owedToMe.isZero;

  /// Positive when the caller is owed overall, negative when they owe.
  Money get net => Money(owedToMe.centavos - owedByMe.centavos);
}

/// A row in "Needs your attention" on Home (spec §10).
@freezed
abstract class OpenShare with _$OpenShare {
  const factory OpenShare({
    required String billId,
    required String billTitle,
    required DateTime billDate,
    required String groupId,
    required String groupName,
    required String payerId,
    required String payerName,
    @MoneyConverter() required Money amount,
    required String status,
  }) = _OpenShare;

  const OpenShare._();

  factory OpenShare.fromJson(Map<String, dynamic> json) =>
      _$OpenShareFromJson(json);

  bool get isAwaitingConfirmation => status == 'pending_confirmation';
}
