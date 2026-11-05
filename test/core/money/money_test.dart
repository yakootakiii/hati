import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  test('en_PH date symbols are available once initialised', () async {
    // main() calls this before runApp. Without it DateFormat throws
    // LocaleDataException the first time a bill date is rendered — intl ships
    // only en_US compiled in.
    await initializeDateFormatting('en_PH');
    expect(
      DateFormat.yMMMd('en_PH').format(DateTime.utc(2026, 9, 20)),
      isNotEmpty,
    );
  });

  group('Money.of', () {
    test('combines pesos and centavos', () {
      expect(Money.of(12500, 50).centavos, 1250050);
      expect(Money.of(12500).centavos, 1250000);
    });

    test('keeps the sign on the centavo part', () {
      expect(Money.of(-1, 50).centavos, -150);
    });

    test('rejects out-of-range centavos', () {
      expect(() => Money.of(1, 100), throwsArgumentError);
      expect(() => Money.of(1, -1), throwsArgumentError);
    });
  });

  group('Money.tryParse', () {
    test('accepts plain, grouped, symboled and short-decimal input', () {
      expect(Money.tryParse('12500'), const Money(1250000));
      expect(Money.tryParse('12,500.50'), const Money(1250050));
      expect(Money.tryParse('₱12,500.00'), const Money(1250000));
      expect(Money.tryParse('12500.5'), const Money(1250050));
      expect(Money.tryParse('-100.25'), const Money(-10025));
    });

    test('rejects malformed input rather than rounding it', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.234'), isNull, reason: 'three decimals');
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('.50'), isNull);
    });
  });

  group('arithmetic', () {
    test('adds, subtracts and scales exactly', () {
      expect(const Money(1250000) + const Money(50), const Money(1250050));
      expect(const Money(1250000) - const Money(50), const Money(1249950));
      expect(const Money(3125) * 4, const Money(12500));
    });

    test('sums a list without drift', () {
      // ₱0.10 a hundred times is exactly ₱10.00 — the classic float failure.
      final tenths = List.filled(100, const Money(10));
      expect(sumMoney(tenths), const Money(1000));
    });

    test('compares and orders', () {
      expect(const Money(100) < const Money(200), isTrue);
      expect(const Money(200) >= const Money(200), isTrue);
      final amounts = [const Money(300), const Money(100), const Money(200)]
        ..sort();
      expect(amounts, [const Money(100), const Money(200), const Money(300)]);
    });
  });

  group('bill total validation (spec §12.10)', () {
    test('accepts amounts up to ₱10,000,000.00', () {
      expect(const Money(kMaxBillCentavos).isValidBillTotal, isTrue);
      expect(const Money(1).isValidBillTotal, isTrue);
    });

    test('rejects zero, negative and oversized totals', () {
      expect(Money.zero.isValidBillTotal, isFalse);
      expect(const Money(-1).isValidBillTotal, isFalse);
      expect(const Money(kMaxBillCentavos + 1).isValidBillTotal, isFalse);
    });
  });

  group('formatting (spec §11)', () {
    test('always shows centavos with the peso symbol', () {
      expect(const Money(1250000).format(), '₱12,500.00');
      expect(const Money(312500).format(), '₱3,125.00');
      expect(const Money(3334).format(), '₱33.34');
    });

    test('formatBare omits the symbol for text fields', () {
      expect(const Money(1250050).formatBare(), '12,500.50');
    });
  });

  test('round-trips through json as an integer', () {
    expect(Money.fromJson(const Money(1250050).toJson()), const Money(1250050));
  });
}
