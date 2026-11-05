import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_models.freezed.dart';
part 'notification_models.g.dart';

/// One notification in the in-app list (spec §10).
@freezed
abstract class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    required String type,
    required String title,
    required String body,
    required DateTime createdAt,
    @Default(<String, dynamic>{}) Map<String, dynamic> data,
    DateTime? readAt,
    DateTime? pushedAt,
  }) = _AppNotification;

  const AppNotification._();

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);

  bool get isUnread => readAt == null;

  /// Where tapping it goes (spec §10).
  String? get route {
    final route = data['route'];
    return route is String && route.isNotEmpty ? route : null;
  }

  /// The invite this notification carries, if it is one (DECISIONS D-57).
  GroupInviteData? get groupInvite {
    if (type != 'group_invite') return null;
    final inviteId = data['invite_id'];
    final groupId = data['group_id'];
    if (inviteId is! String || groupId is! String) return null;
    return GroupInviteData(
      inviteId: inviteId,
      groupId: groupId,
      groupName: data['group_name'] as String? ?? 'the group',
      status: data['status'] as String? ?? 'pending',
    );
  }
}

/// A group invite's payload. The server rewrites [status] when the invite is
/// answered or cancelled, so an old notification stops offering Join.
class GroupInviteData {
  const GroupInviteData({
    required this.inviteId,
    required this.groupId,
    required this.groupName,
    required this.status,
  });

  final String inviteId;
  final String groupId;
  final String groupName;
  final String status;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  /// Replaces the body once there is an answer; null while pending.
  String? get outcome => switch (status) {
    'accepted' => 'You joined. Tap to open the group.',
    'declined' => 'You declined.',
    'cancelled' => 'This invite was cancelled.',
    _ => null,
  };
}

/// The five switches from spec §5.1.
@freezed
abstract class NotificationPrefs with _$NotificationPrefs {
  const factory NotificationPrefs({
    @Default(true) bool newBill,
    @Default(true) bool paymentMarked,
    @Default(true) bool paymentConfirmed,
    @Default(true) bool comments,
    @Default(true) bool reminders,
  }) = _NotificationPrefs;

  const NotificationPrefs._();

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) =>
      _$NotificationPrefsFromJson(json);

  static const NotificationPrefs allOn = NotificationPrefs();
}
