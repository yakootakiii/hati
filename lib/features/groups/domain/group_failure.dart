/// Why a group or invite operation failed.
///
/// The RPCs raise custom SQLSTATEs (HT001–HT010, listed in the groups RPC
/// migration) which PostgREST passes through as the error code. Mapping on the
/// code rather than the message means the copy can change freely on either
/// side without breaking the other.
enum GroupFailureKind {
  notAMember,
  notAuthorized,
  inviteNotFound,
  inviteExpired,
  inviteRevoked,
  inviteExhausted,
  outstandingBalance,
  ownerMustTransfer,
  cannotRemoveOwner,
  invalidInput,
  directInviteNotFound,
  alreadyMember,
  directInviteAnswered,
  declinedRecently,
  queryTooShort,
  network,
  unknown,
}

class GroupFailure implements Exception {
  const GroupFailure(this.kind, this.message);

  final GroupFailureKind kind;

  /// Server-supplied detail. For [GroupFailureKind.outstandingBalance] it
  /// names the bills that are blocking, which the spec requires (§12.3).
  final String message;

  /// Maps a Postgres SQLSTATE to a failure the UI knows how to render.
  factory GroupFailure.fromCode(String? code, String message) {
    final kind = switch (code) {
      'HT001' => GroupFailureKind.notAMember,
      'HT002' => GroupFailureKind.notAuthorized,
      'HT003' => GroupFailureKind.inviteNotFound,
      'HT004' => GroupFailureKind.inviteExpired,
      'HT005' => GroupFailureKind.inviteRevoked,
      'HT006' => GroupFailureKind.inviteExhausted,
      'HT007' => GroupFailureKind.outstandingBalance,
      'HT008' => GroupFailureKind.ownerMustTransfer,
      'HT009' => GroupFailureKind.cannotRemoveOwner,
      'HT010' => GroupFailureKind.invalidInput,
      'HT070' => GroupFailureKind.directInviteNotFound,
      'HT071' => GroupFailureKind.alreadyMember,
      'HT072' => GroupFailureKind.directInviteAnswered,
      'HT073' => GroupFailureKind.declinedRecently,
      'HT074' => GroupFailureKind.queryTooShort,
      _ => GroupFailureKind.unknown,
    };
    return GroupFailure(kind, message);
  }

  /// What to show the user. Falls back to the server's own message where that
  /// is already the most specific thing available.
  String get displayMessage => switch (kind) {
    GroupFailureKind.inviteNotFound =>
      "That invite link isn't valid. Ask for a new one.",
    GroupFailureKind.inviteExpired =>
      'That invite link has expired. Ask for a new one.',
    GroupFailureKind.inviteRevoked =>
      'That invite link was reset. Ask for a new one.',
    GroupFailureKind.inviteExhausted =>
      'That invite link has been used up. Ask for a new one.',
    GroupFailureKind.directInviteNotFound => 'That invite is no longer there.',
    GroupFailureKind.directInviteAnswered =>
      'That invite was already answered or cancelled.',
    GroupFailureKind.alreadyMember => 'They are already in this group.',
    GroupFailureKind.declinedRecently =>
      'They declined recently. Try again tomorrow.',
    GroupFailureKind.queryTooShort => 'Type at least two characters.',
    GroupFailureKind.network =>
      "Can't reach Hati right now. Check your connection and try again.",
    GroupFailureKind.unknown => 'Something went wrong. Try again.',
    _ => message,
  };

  @override
  String toString() => 'GroupFailure(${kind.name}): $message';
}
