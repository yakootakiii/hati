import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../bills/presentation/bills_controller.dart';
import '../data/notifications_repository.dart';
import '../domain/notification_models.dart';

part 'notifications_controller.g.dart';

@riverpod
Future<List<AppNotification>> notificationList(Ref ref) =>
    ref.watch(notificationsRepositoryProvider).list();

/// Drives the badge on the app bar bell (spec §10).
@riverpod
Future<int> unreadNotificationCount(Ref ref) =>
    ref.watch(notificationsRepositoryProvider).unreadCount();

@riverpod
Future<NotificationPrefs> notificationPrefs(Ref ref) =>
    ref.watch(notificationsRepositoryProvider).prefs();

@Riverpod(keepAlive: true)
class NotificationActions extends _$NotificationActions {
  @override
  FutureOr<void> build() {}

  String? lastError;

  Future<bool> markRead(String id) =>
      _run(() => ref.read(notificationsRepositoryProvider).markRead(id));

  Future<bool> markAllRead() =>
      _run(() => ref.read(notificationsRepositoryProvider).markAllRead());

  Future<bool> savePrefs(NotificationPrefs prefs) => _run(() async {
    await ref.read(notificationsRepositoryProvider).savePrefs(prefs);
    ref.invalidate(notificationPrefsProvider);
  });

  /// Returns true when the nudge went out. A refusal — wrong person, too soon,
  /// already settled — comes back in [lastError].
  Future<bool> nudge({required String billShareId, required String billId}) =>
      _run(() async {
        await ref.read(notificationsRepositoryProvider).nudge(billShareId);
        ref.invalidate(billDetailProvider(billId));
      });

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      ref
        ..invalidate(notificationListProvider)
        ..invalidate(unreadNotificationCountProvider);
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return true;
    } on NotificationFailure catch (failure, stackTrace) {
      lastError = failure.displayMessage;
      state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}
