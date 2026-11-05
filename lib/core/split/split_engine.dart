import '../money/money.dart';
import 'split_models.dart';

/// The split engine (spec §6).
///
/// Pure integer arithmetic on centavos, with a twin in PL/pgSQL
/// (`…0008_split_engine.sql`). Both are driven by the same vectors in
/// `supabase/tests/split_vectors.json`, because §14 requires them to agree
/// exactly and the only way to keep two implementations honest is to make them
/// answer the same questions.
abstract final class SplitEngine {
  /// Splits [request.total] among its participants.
  ///
  /// Throws [SplitException] rather than rounding its way out of invalid
  /// input.
  static SplitResult compute(SplitRequest request) {
    final participants = request.participants;

    if (participants.isEmpty) {
      throw const SplitException(SplitFailure.noParticipants);
    }
    final ids = participants.map((p) => p.userId).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      throw const SplitException(SplitFailure.duplicateParticipant);
    }
    if (!request.total.isValidBillTotal) {
      throw SplitException(
        SplitFailure.invalidTotal,
        '${request.total.centavos} centavos',
      );
    }

    final amounts = switch (request.mode) {
      SplitMode.equal => _equal(request),
      SplitMode.exact => _exact(request),
      SplitMode.percent => _percent(request),
      SplitMode.shares => _shares(request),
      SplitMode.itemized => _itemized(request),
    };

    for (final centavos in amounts) {
      if (centavos < 0) {
        throw const SplitException(SplitFailure.negativeShare);
      }
    }

    return SplitResult(
      total: request.total,
      shares: [
        for (var i = 0; i < participants.length; i++)
          SplitShare(
            userId: participants[i].userId,
            amount: Money(amounts[i]),
            input: participants[i].input,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // the remainder rule (spec §6.2)
  // ---------------------------------------------------------------------

  /// Divides [total] in proportion to [weights], exactly.
  ///
  /// Each share is floored to the centavo, then the leftover centavos are
  /// handed out one each by the largest remainder method, ties broken by
  /// position. That makes the result deterministic, never off by more than a
  /// centavo per person, and identical to what the SQL twin produces.
  ///
  /// The arithmetic stays in integers throughout: `total * weight` divided by
  /// the weight sum, keeping the modulus as the remainder, so nothing is ever
  /// approximated.
  static List<int> distribute(int total, List<int> weights) {
    final weightSum = weights.fold<int>(0, (t, w) => t + w);
    if (weightSum <= 0) {
      throw const SplitException(SplitFailure.nonPositiveWeight);
    }

    final amounts = <int>[];
    final remainders = <int>[];
    for (final weight in weights) {
      final numerator = total * weight;
      amounts.add(numerator ~/ weightSum);
      remainders.add(numerator % weightSum);
    }

    final leftover = total - amounts.fold<int>(0, (t, a) => t + a);

    // Largest remainder first; equal remainders fall back to participant
    // order, which is what makes ₱100 among 3 give the extra centavo to the
    // first person (spec §6.4).
    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });

    for (var i = 0; i < leftover; i++) {
      amounts[order[i]] += 1;
    }
    return amounts;
  }

  // ---------------------------------------------------------------------
  // modes
  // ---------------------------------------------------------------------

  static List<int> _equal(SplitRequest request) => distribute(
        request.total.centavos,
        List<int>.filled(request.participants.length, 1),
      );

  static List<int> _exact(SplitRequest request) {
    final amounts = [
      for (final p in request.participants) p.input ?? 0,
    ];
    final sum = amounts.fold<int>(0, (t, a) => t + a);
    if (sum != request.total.centavos) {
      throw SplitException(
        SplitFailure.exactSumMismatch,
        '$sum != ${request.total.centavos}',
      );
    }
    return amounts;
  }

  /// Percentages arrive as hundredths, so 100.00% is 10000 and the check is
  /// exact rather than a tolerance.
  static const int _wholePercent = 10000;

  static List<int> _percent(SplitRequest request) {
    final percents = [
      for (final p in request.participants) p.input ?? 0,
    ];
    for (final percent in percents) {
      if (percent < 0) {
        throw const SplitException(SplitFailure.nonPositiveWeight);
      }
    }
    final sum = percents.fold<int>(0, (t, p) => t + p);
    if (sum != _wholePercent) {
      throw SplitException(
        SplitFailure.percentSumMismatch,
        '$sum != $_wholePercent',
      );
    }
    return distribute(request.total.centavos, percents);
  }

  static List<int> _shares(SplitRequest request) {
    final weights = [
      for (final p in request.participants) p.input ?? 0,
    ];
    for (final weight in weights) {
      if (weight <= 0) {
        throw const SplitException(SplitFailure.nonPositiveWeight);
      }
    }
    return distribute(request.total.centavos, weights);
  }

  // ---------------------------------------------------------------------
  // itemized (spec §6.3)
  // ---------------------------------------------------------------------

  static List<int> _itemized(SplitRequest request) {
    final index = {
      for (var i = 0; i < request.participants.length; i++)
        request.participants[i].userId: i,
    };
    final count = request.participants.length;
    final subtotals = List<int>.filled(count, 0);

    // Each item is split equally among its assignees, with the remainder rule
    // applied per item — so a ₱10.00 item shared by 3 is 3.34 / 3.33 / 3.33,
    // not a fraction carried forward.
    for (final item in request.items) {
      if (item.assignees.isEmpty) {
        throw SplitException(SplitFailure.itemWithoutAssignees, item.name);
      }
      final positions = <int>[];
      for (final assignee in item.assignees) {
        final position = index[assignee];
        if (position == null) {
          throw SplitException(SplitFailure.unknownAssignee, assignee);
        }
        positions.add(position);
      }

      final portions = distribute(
        item.amount.centavos,
        List<int>.filled(positions.length, 1),
      );
      for (var i = 0; i < positions.length; i++) {
        subtotals[positions[i]] += portions[i];
      }
    }

    final subtotal = subtotals.fold<int>(0, (t, s) => t + s);
    final extras = request.extras;
    final expectedTotal = subtotal +
        extras.serviceCharge.centavos +
        extras.tax.centavos -
        extras.discount.centavos;

    if (expectedTotal != request.total.centavos) {
      throw SplitException(
        SplitFailure.itemsTotalMismatch,
        '$expectedTotal != ${request.total.centavos}',
      );
    }

    // Extras ride on each person's item subtotal, one at a time, in a fixed
    // order (DECISIONS D-05). The order decides who gets a leftover centavo,
    // so it is pinned here and in the SQL twin rather than left to chance.
    final amounts = [...subtotals];
    for (final (extra, sign) in [
      (extras.serviceCharge, 1),
      (extras.tax, 1),
      (extras.discount, -1),
    ]) {
      if (extra.isZero) continue;
      final portions = _spreadOverSubtotals(extra.centavos, subtotals, count);
      for (var i = 0; i < count; i++) {
        amounts[i] += sign * portions[i];
      }
    }
    return amounts;
  }

  /// Spreads an extra across participants in proportion to their item
  /// subtotals.
  ///
  /// When nobody has a subtotal — every item was free — proportion is
  /// meaningless, so the extra is shared equally instead of failing
  /// (DECISIONS D-28).
  static List<int> _spreadOverSubtotals(
    int amount,
    List<int> subtotals,
    int count,
  ) {
    final hasSubtotal = subtotals.any((s) => s > 0);
    return distribute(
      amount,
      hasSubtotal ? subtotals : List<int>.filled(count, 1),
    );
  }
}
