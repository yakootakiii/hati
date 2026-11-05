import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/money/money.dart';
import 'package:hati/core/split/split.dart';

/// The Dart half of the split engine's verification.
///
/// The vectors are shared with `supabase/tests/split_test.sql`: both suites
/// read this one file, so if the two engines ever disagree, one of them goes
/// red (spec §14).
void main() {
  List<Map<String, dynamic>> load(String path) =>
      ((jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
              ['cases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

  final cases = load('supabase/tests/split_vectors.json');

  // The generated corpus is committed, so this pins the engine to it: change
  // the Dart engine without re-running tool/gen_fuzz_vectors.dart and this
  // goes red — the same way the SQL suite goes red if the two diverge.
  final fuzz = load('supabase/tests/split_vectors_fuzz.json');

  group('shared vectors', () {
    test('the files actually have vectors in them', () {
      // Guards against a suite that silently passes because it loaded nothing.
      expect(cases.length, greaterThanOrEqualTo(20));
      expect(cases.where((c) => c.containsKey('error')), isNotEmpty);
      expect(fuzz.length, greaterThanOrEqualTo(200));
      expect(
        fuzz.map((c) => (c['input'] as Map<String, dynamic>)['mode']).toSet(),
        hasLength(SplitMode.values.length),
        reason: 'the corpus should exercise every mode',
      );
    });

    for (final vector in cases) {
      final name = vector['name'] as String;
      final request = SplitRequest.fromJson(
        vector['input'] as Map<String, dynamic>,
      );

      if (vector.containsKey('expect')) {
        test(name, () {
          final result = SplitEngine.compute(request);
          final expected = (vector['expect'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toInt()));

          expect(result.toJson(), expected);

          // The §6.1 invariant, asserted on every single vector rather than
          // trusted from the constructor.
          final sum = result.shares
              .fold<int>(0, (t, s) => t + s.amount.centavos);
          expect(sum, request.total.centavos, reason: 'shares must sum to total');
        });
      } else {
        test(name, () {
          expect(
            () => SplitEngine.compute(request),
            throwsA(
              isA<SplitException>().having(
                (e) => e.failure.slug,
                'failure',
                vector['error'] as String,
              ),
            ),
          );
        });
      }
    }
  });

  test('the committed corpus still matches the engine', () {
    var checked = 0;
    for (final vector in fuzz) {
      final request = SplitRequest.fromJson(
        vector['input'] as Map<String, dynamic>,
      );
      final expected = (vector['expect'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));

      expect(
        SplitEngine.compute(request).toJson(),
        expected,
        reason: vector['name'] as String,
      );
      checked++;
    }
    expect(checked, fuzz.length);
  });

  group('the remainder rule (spec §6.2)', () {
    test('hands leftovers to the largest remainders first', () {
      // Weights 1:1:2 of 7 centavos: exact shares are 1.75, 1.75, 3.5.
      // Floors are 1, 1, 3 leaving 2 centavos; the two largest remainders are
      // the .75s, so they take them.
      expect(SplitEngine.distribute(7, [1, 1, 2]), [2, 2, 3]);
    });

    test('breaks ties by participant order, never at random', () {
      for (var i = 0; i < 20; i++) {
        expect(SplitEngine.distribute(10000, [1, 1, 1]), [3334, 3333, 3333]);
      }
    });

    test('is never off by more than a centavo per person', () {
      final amounts = SplitEngine.distribute(100000, [1, 1, 1, 1, 1, 1, 7]);
      final smallest = amounts.take(6).reduce((a, b) => a < b ? a : b);
      final largest = amounts.take(6).reduce((a, b) => a > b ? a : b);
      expect(largest - smallest, lessThanOrEqualTo(1));
    });

    test('adds up for every participant count up to 50', () {
      for (var n = 1; n <= 50; n++) {
        for (final total in [1, 7, 100, 9999, 1250000, kMaxBillCentavos]) {
          final amounts = SplitEngine.distribute(total, List.filled(n, 1));
          expect(
            amounts.fold<int>(0, (t, a) => t + a),
            total,
            reason: 'n=$n total=$total',
          );
        }
      }
    });

    test('refuses weights that sum to nothing', () {
      expect(
        () => SplitEngine.distribute(100, [0, 0]),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('SplitResult', () {
    test('cannot be built from shares that do not add up', () {
      expect(
        () => SplitResult(
          total: const Money(1000),
          shares: const [SplitShare(userId: 'u1', amount: Money(999))],
        ),
        throwsStateError,
      );
    });

    test('reports zero for someone not on the bill', () {
      final result = SplitEngine.compute(
        const SplitRequest(
          total: Money(1000),
          mode: SplitMode.equal,
          participants: [SplitParticipant(userId: 'u1')],
        ),
      );
      expect(result.amountFor('nobody'), Money.zero);
    });

    test('echoes the raw input back for bill_shares.split_input', () {
      final result = SplitEngine.compute(
        const SplitRequest(
          total: Money(100000),
          mode: SplitMode.percent,
          participants: [
            SplitParticipant(userId: 'u1', input: 2500),
            SplitParticipant(userId: 'u2', input: 7500),
          ],
        ),
      );
      expect(result.shares.map((s) => s.input), [2500, 7500]);
    });
  });
}
