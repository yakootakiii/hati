import 'package:flutter/material.dart';

/// Status colours for money (spec §11).
///
/// Status is never conveyed by colour alone — every use of these pairs with a
/// label or icon. They live in a [ThemeExtension] so light and dark each carry
/// their own tuned values and widgets never reach for a raw hex.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({
    required this.owe,
    required this.onOwe,
    required this.oweContainer,
    required this.owed,
    required this.onOwed,
    required this.owedContainer,
    required this.pending,
    required this.onPending,
    required this.pendingContainer,
  });

  /// Amounts the viewer owes someone else.
  final Color owe;
  final Color onOwe;
  final Color oweContainer;

  /// Amounts someone else owes the viewer.
  final Color owed;
  final Color onOwed;
  final Color owedContainer;

  /// Marked paid, awaiting the payer's confirmation.
  final Color pending;
  final Color onPending;
  final Color pendingContainer;

  /// Tuned per brightness rather than borrowed from the scheme's error and
  /// tertiary roles: red, green and amber that each pass 4.5:1 on the
  /// surface they are drawn on (DECISIONS D-59).
  factory MoneyColors.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return isDark
        ? const MoneyColors(
            owe: Color(0xFFF97066),
            onOwe: Color(0xFF3D0A06),
            oweContainer: Color(0xFF3A1513),
            owed: Color(0xFF47CD89),
            onOwed: Color(0xFF052E1A),
            owedContainer: Color(0xFF0E2C1D),
            pending: Color(0xFFFDB022),
            onPending: Color(0xFF3B2604),
            pendingContainer: Color(0xFF3A2A0B),
          )
        : const MoneyColors(
            owe: Color(0xFFB42318),
            onOwe: Color(0xFFFFFFFF),
            oweContainer: Color(0xFFFDEDEC),
            owed: Color(0xFF067647),
            onOwed: Color(0xFFFFFFFF),
            owedContainer: Color(0xFFE7F6EC),
            pending: Color(0xFFB54708),
            onPending: Color(0xFF7A2E0E),
            pendingContainer: Color(0xFFFEF4E6),
          );
  }

  @override
  MoneyColors copyWith({
    Color? owe,
    Color? onOwe,
    Color? oweContainer,
    Color? owed,
    Color? onOwed,
    Color? owedContainer,
    Color? pending,
    Color? onPending,
    Color? pendingContainer,
  }) {
    return MoneyColors(
      owe: owe ?? this.owe,
      onOwe: onOwe ?? this.onOwe,
      oweContainer: oweContainer ?? this.oweContainer,
      owed: owed ?? this.owed,
      onOwed: onOwed ?? this.onOwed,
      owedContainer: owedContainer ?? this.owedContainer,
      pending: pending ?? this.pending,
      onPending: onPending ?? this.onPending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
    );
  }

  @override
  MoneyColors lerp(covariant MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      owe: Color.lerp(owe, other.owe, t)!,
      onOwe: Color.lerp(onOwe, other.onOwe, t)!,
      oweContainer: Color.lerp(oweContainer, other.oweContainer, t)!,
      owed: Color.lerp(owed, other.owed, t)!,
      onOwed: Color.lerp(onOwed, other.onOwed, t)!,
      owedContainer: Color.lerp(owedContainer, other.owedContainer, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      onPending: Color.lerp(onPending, other.onPending, t)!,
      pendingContainer: Color.lerp(pendingContainer, other.pendingContainer, t)!,
    );
  }
}

extension MoneyColorsX on BuildContext {
  /// `context.money.owe` — the semantic money palette for the current theme.
  MoneyColors get money => Theme.of(this).extension<MoneyColors>()!;
}
