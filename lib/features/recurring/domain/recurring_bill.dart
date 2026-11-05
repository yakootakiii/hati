import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/split/split.dart';

part 'recurring_bill.freezed.dart';
part 'recurring_bill.g.dart';

/// How often a template runs (spec §5.1).
enum RecurrenceFrequency {
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  yearly('yearly', 'Yearly');

  const RecurrenceFrequency(this.wire, this.label);

  final String wire;
  final String label;

  static RecurrenceFrequency fromWire(String value) =>
      RecurrenceFrequency.values.firstWhere(
        (f) => f.wire == value,
        orElse: () => RecurrenceFrequency.monthly,
      );
}

/// A repeating bill (spec §5.1, §10).
@freezed
abstract class RecurringBill with _$RecurringBill {
  const factory RecurringBill({
    required String id,
    required String groupId,
    required String title,
    @MoneyConverter() required Money totalAmount,
    required String paidBy,
    required String splitMode,
    required String frequency,
    required DateTime nextRunOn,
    @Default(1) int interval,
    @Default(false) bool paused,
    @Default(<String>[]) List<String> participantIds,
    String? createdBy,
    String? category,
    String? notes,
    int? anchorDay,
    DateTime? endsOn,
  }) = _RecurringBill;

  const RecurringBill._();

  factory RecurringBill.fromJson(Map<String, dynamic> json) =>
      _$RecurringBillFromJson(json);

  SplitMode get mode => SplitMode.fromJson(splitMode);

  RecurrenceFrequency get cadence => RecurrenceFrequency.fromWire(frequency);

  bool get hasEnded =>
      endsOn != null && nextRunOn.isAfter(endsOn!);

  /// "Monthly on the 1st", "Every 2 weeks" — the line under the title.
  String get scheduleLabel {
    final every = interval > 1 ? 'Every $interval ' : '';

    return switch (cadence) {
      RecurrenceFrequency.weekly =>
        interval > 1 ? '${every}weeks' : 'Weekly',
      RecurrenceFrequency.monthly => interval > 1
          ? '${every}months${_onDay()}'
          : 'Monthly${_onDay()}',
      RecurrenceFrequency.yearly =>
        interval > 1 ? '${every}years' : 'Yearly',
    };
  }

  String _onDay() {
    final day = anchorDay;
    if (day == null) return '';
    return ' on the $day${_ordinal(day)}';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return 'th';
    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}
