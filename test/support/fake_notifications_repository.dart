import 'package:hati/features/notifications/data/notifications_repository.dart';
import 'package:hati/features/notifications/domain/notification_models.dart';

/// An in-memory [NotificationsRepository] for tests.
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository({
    List<AppNotification>? notifications,
    NotificationPrefs? prefs,
  }) : notifications = notifications ?? <AppNotification>[],
       _prefs = prefs ?? NotificationPrefs.allOn;

  final List<AppNotification> notifications;
  NotificationPrefs _prefs;

  /// Fails the next call to any method.
  NotificationFailure? failWith;

  /// Fails only [nudge]. Separate because the bell calls `unreadCount` as soon
  /// as the app boots, which would otherwise swallow a general `failWith`.
  NotificationFailure? nudgeFailure;
  final List<String> calls = <String>[];
  Map<String, Object?> lastArgs = <String, Object?>{};

  @override
  Future<List<AppNotification>> list({int limit = 50}) async {
    calls.add('list');
    _maybeFail();
    return notifications;
  }

  @override
  Future<int> unreadCount() async {
    calls.add('unreadCount');
    _maybeFail();
    return notifications.where((n) => n.isUnread).length;
  }

  @override
  Future<void> markRead(String id) async {
    calls.add('markRead');
    lastArgs = {'id': id};
    _maybeFail();
    final index = notifications.indexWhere((n) => n.id == id);
    if (index >= 0) {
      notifications[index] = notifications[index].copyWith(
        readAt: DateTime.utc(2026, 9, 28),
      );
    }
  }

  @override
  Future<void> markAllRead() async {
    calls.add('markAllRead');
    _maybeFail();
    for (var i = 0; i < notifications.length; i++) {
      notifications[i] = notifications[i].copyWith(
        readAt: DateTime.utc(2026, 9, 28),
      );
    }
  }

  @override
  Future<NotificationPrefs> prefs() async {
    calls.add('prefs');
    _maybeFail();
    return _prefs;
  }

  @override
  Future<void> savePrefs(NotificationPrefs prefs) async {
    calls.add('savePrefs');
    lastArgs = {'prefs': prefs};
    _maybeFail();
    _prefs = prefs;
  }

  @override
  Future<void> nudge(String billShareId) async {
    calls.add('nudge');
    lastArgs = {'billShareId': billShareId};
    final specific = nudgeFailure;
    if (specific != null) {
      nudgeFailure = null;
      throw specific;
    }
    _maybeFail();
  }

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) async {
    calls.add('registerDevice');
    lastArgs = {'token': token, 'platform': platform};
    _maybeFail();
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
