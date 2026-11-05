/// Why a settlement action failed (spec §7 HT040–HT048, HT054–HT056).
enum SettlementFailureKind {
  shareNotFound,
  notTheDebtor,
  notThePayer,
  shareAlreadySettled,
  paymentNotFound,
  alreadyDecided,
  billVoided,
  proofRequired,
  notYourMethod,
  emptyBatch,
  mixedBatch,
  batchAlreadyPaid,
  notAuthorized,
  network,
  unknown,
}

class SettlementFailure implements Exception {
  const SettlementFailure(this.kind, this.message);

  final SettlementFailureKind kind;
  final String message;

  factory SettlementFailure.fromCode(String? code, String message) {
    final kind = switch (code) {
      'HT002' => SettlementFailureKind.notAuthorized,
      'HT040' => SettlementFailureKind.shareNotFound,
      'HT041' => SettlementFailureKind.notTheDebtor,
      'HT042' => SettlementFailureKind.notThePayer,
      'HT043' => SettlementFailureKind.shareAlreadySettled,
      'HT044' => SettlementFailureKind.paymentNotFound,
      'HT045' => SettlementFailureKind.alreadyDecided,
      'HT046' => SettlementFailureKind.billVoided,
      'HT047' => SettlementFailureKind.proofRequired,
      'HT048' => SettlementFailureKind.notYourMethod,
      'HT054' => SettlementFailureKind.emptyBatch,
      'HT055' => SettlementFailureKind.mixedBatch,
      'HT056' => SettlementFailureKind.batchAlreadyPaid,
      _ => SettlementFailureKind.unknown,
    };
    return SettlementFailure(kind, message);
  }

  String get displayMessage => switch (kind) {
        SettlementFailureKind.notThePayer =>
          'Only whoever paid the bill can confirm or reject a payment.',
        SettlementFailureKind.notTheDebtor =>
          'Only the person who owes this can mark it paid.',
        SettlementFailureKind.shareAlreadySettled =>
          'That one is already settled.',
        SettlementFailureKind.alreadyDecided =>
          'Someone already handled that payment.',
        SettlementFailureKind.billVoided => 'That bill was voided.',
        SettlementFailureKind.proofRequired =>
          'Attach a screenshot of your payment first.',
        SettlementFailureKind.notYourMethod =>
          'You can only be paid through your own payment methods.',
        SettlementFailureKind.emptyBatch => 'Pick at least one bill to settle.',
        SettlementFailureKind.mixedBatch =>
          'Those bills are not all owed to the same person in this group.',
        SettlementFailureKind.batchAlreadyPaid =>
          'One of those bills was already paid. Refresh and try again.',
        SettlementFailureKind.network =>
          "Can't reach Hati right now. Check your connection and try again.",
        SettlementFailureKind.unknown => 'Something went wrong. Try again.',
        _ => message,
      };

  @override
  String toString() => 'SettlementFailure(${kind.name}): $message';
}
