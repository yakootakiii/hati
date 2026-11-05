import 'package:freezed_annotation/freezed_annotation.dart';

part 'group_models.g.dart';
part 'group_models.freezed.dart';

/// A group as the Groups list needs it (spec §10).
@freezed
abstract class GroupSummary with _$GroupSummary {
  const factory GroupSummary({
    required String id,
    required String name,
    required String role,
    required int memberCount,
    @Default(<GroupMemberProfile>[]) List<GroupMemberProfile> members,
    String? photoPath,
    DateTime? archivedAt,
    DateTime? joinedAt,
  }) = _GroupSummary;

  const GroupSummary._();

  factory GroupSummary.fromJson(Map<String, dynamic> json) =>
      _$GroupSummaryFromJson(json);

  bool get isArchived => archivedAt != null;
  bool get canInvite => role == 'owner' || role == 'admin';
  bool get isOwner => role == 'owner';
}

/// Enough of a profile to draw an avatar and a name.
@freezed
abstract class GroupMemberProfile with _$GroupMemberProfile {
  const factory GroupMemberProfile({
    required String id,
    required String displayName,
    String? avatarPath,
  }) = _GroupMemberProfile;

  factory GroupMemberProfile.fromJson(Map<String, dynamic> json) =>
      _$GroupMemberProfileFromJson(json);
}

/// A row on the Members screen.
@freezed
abstract class GroupMember with _$GroupMember {
  const factory GroupMember({
    required String userId,
    required String displayName,
    required String role,
    String? avatarPath,
    DateTime? joinedAt,
  }) = _GroupMember;

  const GroupMember._();

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';

  /// Spec §11: never convey status by colour alone.
  String get roleLabel => switch (role) {
    'owner' => 'Owner',
    'admin' => 'Admin',
    _ => 'Member',
  };
}

/// The live invite link for a group.
@freezed
abstract class InviteLink with _$InviteLink {
  const factory InviteLink({
    required String id,
    required String token,
    DateTime? expiresAt,
    int? maxUses,
    @Default(0) int useCount,
  }) = _InviteLink;

  const InviteLink._();

  factory InviteLink.fromJson(Map<String, dynamic> json) =>
      _$InviteLinkFromJson(json);

  /// The canonical shareable URL (spec §8): Firebase Hosting, which Android
  /// verifies belongs to Hati, so tapping it opens the app (DECISIONS D-69).
  static const String host = 'https://hati-a1a23.web.app';

  String get url => '$host/join/$token';

  bool get isExhausted => maxUses != null && useCount >= maxUses!;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());
}

/// Why an invite cannot be used. Mirrors the reasons `get_invite_preview`
/// returns.
enum InviteInvalidReason { notFound, expired, revoked, exhausted }

/// What the Join screen shows before the user commits (spec §8.2).
@freezed
sealed class InvitePreview with _$InvitePreview {
  const factory InvitePreview.valid({
    required String groupId,
    required String groupName,
    required int memberCount,
    required bool alreadyMember,
    String? groupPhotoPath,
    String? inviterName,
  }) = ValidInvitePreview;

  /// Carries no group details on purpose: revealing the group behind a revoked
  /// link would make revoking it pointless.
  const factory InvitePreview.invalid(InviteInvalidReason reason) =
      InvalidInvitePreview;

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    if (json['valid'] == true) {
      return InvitePreview.valid(
        groupId: json['group_id'] as String,
        groupName: json['group_name'] as String,
        memberCount: (json['member_count'] as num).toInt(),
        alreadyMember: json['already_member'] as bool? ?? false,
        groupPhotoPath: json['group_photo_path'] as String?,
        inviterName: json['inviter_name'] as String?,
      );
    }
    return InvitePreview.invalid(switch (json['reason'] as String?) {
      'expired' => InviteInvalidReason.expired,
      'revoked' => InviteInvalidReason.revoked,
      'exhausted' => InviteInvalidReason.exhausted,
      _ => InviteInvalidReason.notFound,
    });
  }
}

/// A bill standing in the way of someone leaving (spec §12.3).
@freezed
abstract class LeaveBlocker with _$LeaveBlocker {
  const factory LeaveBlocker({
    required String billId,
    required String title,
    required String reason,
    required int amount,
  }) = _LeaveBlocker;

  const LeaveBlocker._();

  factory LeaveBlocker.fromJson(Map<String, dynamic> json) =>
      _$LeaveBlockerFromJson(json);

  bool get isOwedToThem => reason == 'owed_to_you';
}

/// Someone an owner or admin could invite by name (DECISIONS D-57).
@freezed
abstract class PersonResult with _$PersonResult {
  const factory PersonResult({
    required String id,
    required String displayName,

    /// 'member', 'pending', or null when they can be invited.
    String? status,

    /// Set while [status] is 'pending', so the invite can be cancelled.
    String? inviteId,
  }) = _PersonResult;

  const PersonResult._();

  factory PersonResult.fromJson(Map<String, dynamic> json) =>
      _$PersonResultFromJson(json);

  bool get isMember => status == 'member';
  bool get isPending => status == 'pending';
}

/// An invite waiting on the signed-in user (DECISIONS D-57).
@freezed
abstract class DirectInvite with _$DirectInvite {
  const factory DirectInvite({
    required String id,
    required String groupId,
    required String groupName,
    required String inviterName,
    required int memberCount,
    required DateTime createdAt,
  }) = _DirectInvite;

  factory DirectInvite.fromJson(Map<String, dynamic> json) =>
      _$DirectInviteFromJson(json);
}
