import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

/// The largest amount any single bill may carry: ₱10,000,000.00 (spec §12.10).
const int kMaxBillCentavos = 1000000000;

/// An amount of Philippine pesos, stored exactly as integer centavos.
///
/// Money is never a [double] anywhere in this app (spec §4.1). Construct from
/// centavos, from a user-typed string, or from a peso/centavo pair — never from
/// a floating-point value.
final class Money implements Comparable<Money> {
  const Money(this.centavos);

  /// Builds an amount from whole pesos and centavos, e.g. `Money.of(12500, 50)`
  /// is ₱12,500.50.
  factory Money.of(int pesos, [int centavos = 0]) {
    if (centavos < 0 || centavos > 99) {
      throw ArgumentError.value(centavos, 'centavos', 'must be 0–99');
    }
    final sign = pesos.isNegative ? -1 : 1;
    return Money(pesos * 100 + sign * centavos);
  }

  /// Round-trips through the integer stored in the database.
  factory Money.fromJson(int centavos) => Money(centavos);

  static const Money zero = Money(0);

  final int centavos;

  /// Parses user input such as `12,500.50`, `₱12500`, or `12500.5`.
  ///
  /// Returns null when the text is not a well-formed amount. Accepts at most
  /// two decimal places so that no rounding is ever implied.
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[₱,\s]'), '');
    if (cleaned.isEmpty) return null;

    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;

    final negative = match.group(1) == '-';
    final pesos = int.parse(match.group(2)!);
    final fraction = match.group(3) ?? '';
    final centavos = switch (fraction.length) {
      0 => 0,
      1 => int.parse(fraction) * 10,
      _ => int.parse(fraction),
    };

    final total = pesos * 100 + centavos;
    return Money(negative ? -total : total);
  }

  bool get isZero => centavos == 0;
  bool get isNegative => centavos < 0;
  bool get isPositive => centavos > 0;

  Money operator +(Money other) => Money(centavos + other.centavos);
  Money operator -(Money other) => Money(centavos - other.centavos);

  /// Scales by a whole factor. Fractional splitting belongs in the split
  /// engine, which distributes remainder centavos explicitly (spec §6.2).
  Money operator *(int factor) => Money(centavos * factor);

  bool operator <(Money other) => centavos < other.centavos;
  bool operator <=(Money other) => centavos <= other.centavos;
  bool operator >(Money other) => centavos > other.centavos;
  bool operator >=(Money other) => centavos >= other.centavos;

  Money get negated => Money(-centavos);
  Money get abs => Money(centavos.abs());

  /// True when this amount is a legal bill total (spec §12.10).
  bool get isValidBillTotal => centavos > 0 && centavos <= kMaxBillCentavos;

  /// `₱12,500.00` — always with centavos (spec §11).
  String format() => _pesoFormat.format(_asDecimal);

  /// `12,500.00` — for text fields, where the symbol is shown as a prefix.
  String formatBare() => _bareFormat.format(_asDecimal);

  int toJson() => centavos;

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  @override
  bool operator ==(Object other) => other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() => format();

  // The only place an amount becomes a decimal is the final display step,
  // after all arithmetic is done in integers. Amounts within the ±₱10,000,000
  // range are far inside the exact-integer range of a double, so formatting is
  // lossless.
  num get _asDecimal => centavos / 100; // money-ok: display only, after all integer arithmetic
}

final NumberFormat _pesoFormat =
    NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final NumberFormat _bareFormat = NumberFormat('#,##0.00', 'en_PH');

/// Sums a list of amounts exactly.
Money sumMoney(Iterable<Money> amounts) =>
    Money(amounts.fold(0, (total, m) => total + m.centavos));

/// Lets freezed models carry [Money] fields while the wire stays integer
/// centavos, exactly as the `bigint` columns store it.
class MoneyConverter implements JsonConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromJson(int json) => Money(json);

  @override
  int toJson(Money object) => object.centavos;
}
