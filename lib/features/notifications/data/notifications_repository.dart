import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/notification_models.dart';

part 'notifications_repository.g.dart';

enum NotificationFailureKind {
  shareNotFound,
  notThePayer,
  nothingToNudge,
  nudgedTooRecently,
  network,
  unknown,
}

/// Why a notification action failed (spec §7.2, HT050–HT053).
class NotificationFailure implements Exception {
  const NotificationFailure(this.kind, this.message);

  final NotificationFailureKind kind;
  final String message;

  factory NotificationFailure.fromCode(String? code, String message) {
    final kind = switch (code) {
      'HT050' => NotificationFailureKind.shareNotFound,
      'HT051' => NotificationFailureKind.notThePayer,
      'HT052' => NotificationFailureKind.nothingToNudge,
      'HT053' => NotificationFailureKind.nudgedTooRecently,
      _ => NotificationFailureKind.unknown,
    };
    return NotificationFailure(kind, message);
  }

  String get displayMessage => switch (kind) {
    NotificationFailureKind.notThePayer =>
      'Only whoever paid the bill can nudge.',
    NotificationFailureKind.nudgedTooRecently =>
      'You already nudged them today. Give it a day.',
    NotificationFailureKind.nothingToNudge => 'That one is already settled.',
    NotificationFailureKind.network =>
      "Can't reach Hati right now. Check your connection and try again.",
    _ => 'Something went wrong. Try again.',
  };

  @override
  String toString() => 'NotificationFailure(${kind.name}): $message';
}

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> list({int limit = 50});

  Future<int> unreadCount();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  Future<NotificationPrefs> prefs();

  Future<void> savePrefs(NotificationPrefs prefs);

  /// The payer prods a debtor. Rate-limited to once a day per share (§7.2).
  Future<void> nudge(String billShareId);

  /// Registers this device for push. Does nothing until FCM exists (D-08).
  Future<void> registerDevice({
    required String token,
    required String platform,
  });
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<List<AppNotification>> list({int limit = 50}) {
    return _guard(() async {
      // RLS already restricts this to the caller's own rows.
      final rows = await _client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(AppNotification.fromJson).toList(growable: false);
    });
  }

  @override
  Future<int> unreadCount() {
    return _guard(() async {
      final rows = await _client
          .from('notifications')
          .select('id')
          .isFilter('read_at', null);
      return rows.length;
    });
  }

  @override
  Future<void> markRead(String id) => _guard(
    () => _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id),
  );

  @override
  Future<void> markAllRead() => _guard(
    () => _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null),
  );

  @override
  Future<NotificationPrefs> prefs() {
    return _guard(() async {
      final row = await _client
          .from('notification_prefs')
          .select()
          .eq('user_id', _userId!)
          .maybeSingle();
      // The signup trigger creates the row; everything on is the documented
      // default if it is somehow missing.
      return row == null
          ? NotificationPrefs.allOn
          : NotificationPrefs.fromJson(row);
    });
  }

  @override
  Future<void> savePrefs(NotificationPrefs prefs) => _guard(
    () => _client
        .from('notification_prefs')
        .update({
          'new_bill': prefs.newBill,
          'payment_marked': prefs.paymentMarked,
          'payment_confirmed': prefs.paymentConfirmed,
          'comments': prefs.comments,
          'reminders': prefs.reminders,
        })
        .eq('user_id', _userId!),
  );

  @override
  Future<void> nudge(String billShareId) => _guard(
    () => _client.rpc<void>(
      'nudge_share',
      params: {'p_bill_share_id': billShareId},
    ),
  );

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) => _guard(
    () => _client.from('device_tokens').upsert({
      'user_id': _userId,
      'token': token,
      'platform': platform,
    }, onConflict: 'token'),
  );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw NotificationFailure.fromCode(error.code, error.message);
    } on SocketException catch (_) {
      throw const NotificationFailure(
        NotificationFailureKind.network,
        "Can't reach Hati right now.",
      );
    }
  }
}

@Riverpod(keepAlive: true)
NotificationsRepository notificationsRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Notifications need a Supabase project.');
  }
  return SupabaseNotificationsRepository(Supabase.instance.client);
}
