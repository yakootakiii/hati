import '../money/money.dart';

/// How a bill's total is divided among its participants (spec §6.3).
enum SplitMode {
  equal,
  exact,
  percent,
  shares,
  itemized;

  static SplitMode fromJson(String value) =>
      SplitMode.values.firstWhere((m) => m.name == value);

  String toJson() => name;
}

/// Why a split cannot be computed (spec §6.3 validation, §6.4 rejects).
///
/// [slug] is the wire name shared with the PL/pgSQL engine and with
/// `supabase/tests/split_vectors.json`, so both implementations name the same
/// failure the same way.
enum SplitFailure {
  noParticipants('no_participants'),
  duplicateParticipant('duplicate_participant'),
  invalidTotal('invalid_total'),
  exactSumMismatch('exact_sum_mismatch'),
  percentSumMismatch('percent_sum_mismatch'),
  nonPositiveWeight('non_positive_weight'),
  itemWithoutAssignees('item_without_assignees'),
  unknownAssignee('unknown_assignee'),
  itemsTotalMismatch('items_total_mismatch'),
  negativeShare('negative_share');

  const SplitFailure(this.slug);

  final String slug;

  static SplitFailure fromSlug(String slug) =>
      SplitFailure.values.firstWhere((f) => f.slug == slug);
}

class SplitException implements Exception {
  const SplitException(this.failure, [this.detail]);

  final SplitFailure failure;
  final String? detail;

  @override
  String toString() =>
      'SplitException(${failure.slug}${detail == null ? '' : ': $detail'})';
}

/// A participant and the mode-specific number the user typed for them.
///
/// Every input is an integer on purpose — the Dart and PL/pgSQL engines must
/// agree to the centavo (spec §14), and integers leave no room for the two to
/// round differently:
///
/// | mode     | [input]                                   |
/// |----------|-------------------------------------------|
/// | equal    | null                                      |
/// | exact    | centavos owed                             |
/// | percent  | hundredths of a percent (33.33% → 3333)   |
/// | shares   | thousandths of a share (0.5 → 500)        |
/// | itemized | null — assignment happens on the items    |
class SplitParticipant {
  const SplitParticipant({required this.userId, this.input});

  final String userId;
  final int? input;

  factory SplitParticipant.fromJson(Map<String, dynamic> json) =>
      SplitParticipant(
        userId: json['user_id'] as String,
        input: (json['input'] as num?)?.toInt(),
      );
}

/// A line on an itemized bill (spec §6.3).
class SplitItem {
  const SplitItem({
    required this.name,
    required this.amount,
    required this.assignees,
  });

  final String name;
  final Money amount;

  /// Who shares this line. Must not be empty.
  final List<String> assignees;

  factory SplitItem.fromJson(Map<String, dynamic> json) => SplitItem(
        name: json['name'] as String? ?? '',
        amount: Money((json['amount'] as num).toInt()),
        assignees: (json['assignees'] as List<dynamic>).cast<String>(),
      );
}

/// Service charge, tax and discount on an itemized bill.
///
/// Stored on `bills.itemized_extras` (DECISIONS D-02).
class ItemizedExtras {
  const ItemizedExtras({
    this.serviceCharge = Money.zero,
    this.tax = Money.zero,
    this.discount = Money.zero,
  });

  final Money serviceCharge;
  final Money tax;
  final Money discount;

  static const ItemizedExtras none = ItemizedExtras();

  bool get isEmpty =>
      serviceCharge.isZero && tax.isZero && discount.isZero;

  factory ItemizedExtras.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    Money read(String key) => Money(((json[key] as num?) ?? 0).toInt());
    return ItemizedExtras(
      serviceCharge: read('service_charge'),
      tax: read('tax'),
      discount: read('discount'),
    );
  }
}

/// Everything needed to compute a split.
class SplitRequest {
  const SplitRequest({
    required this.total,
    required this.mode,
    required this.participants,
    this.items = const <SplitItem>[],
    this.extras = ItemizedExtras.none,
  });

  final Money total;
  final SplitMode mode;

  /// Ordered by `group_members.joined_at`, then `user_id` (spec §6.1). The
  /// order is load-bearing: it breaks ties when leftover centavos are handed
  /// out (spec §6.2).
  final List<SplitParticipant> participants;

  final List<SplitItem> items;
  final ItemizedExtras extras;

  factory SplitRequest.fromJson(Map<String, dynamic> json) => SplitRequest(
        total: Money((json['total'] as num).toInt()),
        mode: SplitMode.fromJson(json['mode'] as String),
        participants: (json['participants'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(SplitParticipant.fromJson)
            .toList(growable: false),
        items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(SplitItem.fromJson)
            .toList(growable: false),
        extras: ItemizedExtras.fromJson(
          json['extras'] as Map<String, dynamic>?,
        ),
      );
}

/// One participant's computed share.
class SplitShare {
  const SplitShare({required this.userId, required this.amount, this.input});

  final String userId;
  final Money amount;

  /// Echoed back for `bill_shares.split_input`.
  final int? input;
}

/// The result of a split.
///
/// The sum-equals-total invariant (spec §6.1) is checked on construction, so a
/// [SplitResult] cannot exist in an invalid state.
class SplitResult {
  SplitResult({required this.total, required this.shares}) {
    final sum = shares.fold<int>(0, (t, s) => t + s.amount.centavos);
    if (sum != total.centavos) {
      throw StateError(
        'split does not add up: $sum != ${total.centavos}',
      );
    }
  }

  final Money total;
  final List<SplitShare> shares;

  Money amountFor(String userId) => shares
      .firstWhere(
        (s) => s.userId == userId,
        orElse: () => SplitShare(userId: userId, amount: Money.zero),
      )
      .amount;

  /// `{user_id: centavos}` — the shape the vectors compare against and the
  /// shape the PL/pgSQL engine returns.
  Map<String, int> toJson() => {
        for (final share in shares) share.userId: share.amount.centavos,
      };
}
