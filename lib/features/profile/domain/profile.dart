import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// A user's public profile (spec §5.1).
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    required String displayName,
    String? avatarPath,
  }) = _Profile;

  const Profile._();

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  bool get hasAvatar => avatarPath != null && avatarPath!.isNotEmpty;

  /// The letter shown when there is no avatar. [UserAvatar] does the same for
  /// anyone who is not a full Profile.
  String get initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }
}
