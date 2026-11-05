import '../../../core/split/split.dart';

/// Why a bill operation failed.
///
/// Two families of code arrive from the server and are kept apart on purpose:
/// the bill RPCs raise `HT030`–`HT036`, and the split engine raises
/// `HT020`–`HT029` (DECISIONS D-30). Split failures are input the Add-bill form
/// could have caught, so they surface against the split section rather than as
/// a general error.
enum BillFailureKind {
  notAMember,
  notAuthorized,
  billNotFound,
  payerNotMember,
  participantNotMember,
  lockedByPayment,
  hasConfirmedPayment,
  notAllowed,
  billVoided,
  invalidInput,
  splitInvalid,
  network,
  unknown,
}

class BillFailure implements Exception {
  const BillFailure(this.kind, this.message, {this.splitFailure});

  final BillFailureKind kind;
  final String message;

  /// Set when the server rejected the split itself, so the form can point at
  /// the offending field.
  final SplitFailure? splitFailure;

  factory BillFailure.fromCode(String? code, String message) {
    // The split engine's own range. `message` is the failure slug.
    if (code != null && _splitCodes.containsKey(code)) {
      final failure = _splitCodes[code]!;
      return BillFailure(
        BillFailureKind.splitInvalid,
        _splitCopy(failure),
        splitFailure: failure,
      );
    }

    final kind = switch (code) {
      'HT001' => BillFailureKind.notAMember,
      'HT002' => BillFailureKind.notAuthorized,
      'HT010' => BillFailureKind.invalidInput,
      'HT030' => BillFailureKind.billNotFound,
      'HT031' => BillFailureKind.payerNotMember,
      'HT032' => BillFailureKind.participantNotMember,
      'HT033' => BillFailureKind.lockedByPayment,
      'HT034' => BillFailureKind.hasConfirmedPayment,
      'HT035' => BillFailureKind.notAllowed,
      'HT036' => BillFailureKind.billVoided,
      _ => BillFailureKind.unknown,
    };
    return BillFailure(kind, message);
  }

  static const Map<String, SplitFailure> _splitCodes = {
    'HT020': SplitFailure.noParticipants,
    'HT021': SplitFailure.duplicateParticipant,
    'HT022': SplitFailure.invalidTotal,
    'HT023': SplitFailure.exactSumMismatch,
    'HT024': SplitFailure.percentSumMismatch,
    'HT025': SplitFailure.nonPositiveWeight,
    'HT026': SplitFailure.itemWithoutAssignees,
    'HT027': SplitFailure.unknownAssignee,
    'HT028': SplitFailure.itemsTotalMismatch,
    'HT029': SplitFailure.negativeShare,
  };

  static String _splitCopy(SplitFailure failure) => switch (failure) {
        SplitFailure.noParticipants => 'Pick at least one person to split with.',
        SplitFailure.duplicateParticipant => 'Someone is listed twice.',
        SplitFailure.invalidTotal =>
          'Enter an amount between ₱0.01 and ₱10,000,000.00.',
        SplitFailure.exactSumMismatch =>
          "The amounts don't add up to the total yet.",
        SplitFailure.percentSumMismatch => 'The percentages must add up to 100%.',
        SplitFailure.nonPositiveWeight => 'Every share has to be more than zero.',
        SplitFailure.itemWithoutAssignees =>
          'Every item needs at least one person on it.',
        SplitFailure.unknownAssignee =>
          'An item is assigned to someone who is not on this bill.',
        SplitFailure.itemsTotalMismatch =>
          "The items and extras don't add up to the total.",
        SplitFailure.negativeShare => 'That discount leaves someone owing less than nothing.',
      };

  String get displayMessage => switch (kind) {
        BillFailureKind.lockedByPayment =>
          'Someone has already paid. Void this bill and add it again instead.',
        BillFailureKind.hasConfirmedPayment =>
          "This bill is already settled, so it can't be voided.",
        BillFailureKind.billVoided => 'This bill was voided.',
        BillFailureKind.billNotFound => 'That bill no longer exists.',
        BillFailureKind.network =>
          "Can't reach Hati right now. Check your connection and try again.",
        BillFailureKind.unknown => 'Something went wrong. Try again.',
        _ => message,
      };

  @override
  String toString() => 'BillFailure(${kind.name}): $message';
}
