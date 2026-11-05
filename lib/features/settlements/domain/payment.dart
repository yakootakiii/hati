import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../profile/domain/payment_method.dart';

part 'payment.freezed.dart';
part 'payment.g.dart';

/// One attempt to settle a share (spec §5.1).
@freezed
abstract class Payment with _$Payment {
  const factory Payment({
    required String id,
    required String billShareId,
    required String fromUser,
    required String toUser,
    @MoneyConverter() required Money amount,
    required String status,
    String? method,
    String? referenceNo,
    String? proofPath,
    String? rejectedReason,
    /// Set when one payment covered several bills (DECISIONS D-67).
    String? batchId,
    DateTime? confirmedAt,
    DateTime? createdAt,
  }) = _Payment;

  const Payment._();

  factory Payment.fromJson(Map<String, dynamic> json) =>
      _$PaymentFromJson(json);

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isRejected => status == 'rejected';

  String get methodLabel => switch (method) {
        null => 'Other',
        'cash' => 'Cash',
        final wire => PaymentMethodType.fromWire(wire).label,
      };
}
