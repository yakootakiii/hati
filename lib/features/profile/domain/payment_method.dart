import 'package:freezed_annotation/freezed_annotation.dart';

part 'payment_method.freezed.dart';
part 'payment_method.g.dart';

/// Where to send someone money (spec §9).
///
/// Hati never moves money itself (§2) — this is the information a debtor needs
/// in order to pay outside the app.
enum PaymentMethodType {
  gcash('gcash', 'GCash', isEWallet: true),
  maya('maya', 'Maya', isEWallet: true),
  gotyme('gotyme', 'GoTyme', isEWallet: true),
  shopeepay('shopeepay', 'ShopeePay', isEWallet: true),
  grabpay('grabpay', 'GrabPay', isEWallet: true),
  coinsph('coinsph', 'Coins.ph', isEWallet: true),
  palawanpay('palawanpay', 'PalawanPay', isEWallet: true),
  // A digital bank rather than an e-wallet: paid to an account number.
  maribank('maribank', 'MariBank'),
  bank('bank', 'Bank transfer'),
  other('other', 'Other');

  const PaymentMethodType(this.wire, this.label, {this.isEWallet = false});

  final String wire;
  final String label;

  /// Paid to a mobile number, usually by scanning a QR — as opposed to a bank
  /// account number.
  final bool isEWallet;

  static PaymentMethodType fromWire(String value) =>
      PaymentMethodType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => PaymentMethodType.other,
      );
}

@freezed
abstract class PaymentMethod with _$PaymentMethod {
  const factory PaymentMethod({
    required String id,
    required String userId,
    required String type,
    required String accountName,
    required String accountNumber,
    String? label,
    String? qrImagePath,
    @Default(false) bool isDefault,
  }) = _PaymentMethod;

  const PaymentMethod._();

  factory PaymentMethod.fromJson(Map<String, dynamic> json) =>
      _$PaymentMethodFromJson(json);

  PaymentMethodType get kind => PaymentMethodType.fromWire(type);

  /// What to show as the method's name: the user's own label if they gave one,
  /// otherwise the wallet's name.
  String get displayLabel =>
      (label != null && label!.trim().isNotEmpty) ? label!.trim() : kind.label;

  bool get hasQr => qrImagePath != null && qrImagePath!.isNotEmpty;
}
