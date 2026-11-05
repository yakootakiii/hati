import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/notifications/presentation/notifications_controller.dart';
import '../supabase/supabase_providers.dart';
import 'push_messaging.dart';

part 'push_registration.g.dart';

/// Where this phone's push token is recorded, so the server knows where to
/// deliver (DECISIONS D-65).
abstract interface class DeviceTokenRepository {
  Future<void> register({required String token, required String platform});
  Future<void> unregister(String token);
}

class SupabaseDeviceTokenRepository implements DeviceTokenRepository {
  SupabaseDeviceTokenRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register({required String token, required String platform}) =>
      _client.rpc<void>(
        'register_device_token',
        params: {'p_token': token, 'p_platform': platform},
      );

  @override
  Future<void> unregister(String token) => _client.rpc<void>(
        'unregister_device_token',
        params: {'p_token': token},
      );
}

@Riverpod(keepAlive: true)
PushMessaging pushMessaging(Ref ref) =>
    ref.watch(isBackendConfiguredProvider)
        ? FirebasePushMessaging()
        : const DisabledPushMessaging();

@Riverpod(keepAlive: true)
DeviceTokenRepository deviceTokenRepository(Ref ref) =>
    SupabaseDeviceTokenRepository(Supabase.instance.client);

/// Registers the phone while someone is signed in, opens the screen a tapped
/// notification points at, and refreshes the bell when a push arrives with
/// the app open.
///
/// Push is best effort: every failure here is logged and swallowed, because
/// no part of Hati may depend on a notification arriving.
@Riverpod(keepAlive: true)
class PushRegistration extends _$PushRegistration {
  String? _token;
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  bool build() {
    ref.onDispose(() {
      for (final s in _subscriptions) {
        s.cancel();
      }
    });

    ref.listen(
      sessionStateProvider,
      (previous, next) {
        // Only on the way in: token refreshes and taps are wired once.
        if (next.isSignedIn && !(previous?.isSignedIn ?? false)) {
          unawaited(_start());
        }
      },
      fireImmediately: true,
    );
    return false;
  }

  Future<void> _start() async {
    final messaging = ref.read(pushMessagingProvider);
    try {
      if (!await messaging.initialize()) return;

      if (_subscriptions.isEmpty) {
        _subscriptions
          ..add(messaging.tokenRefreshes.listen(_register))
          ..add(messaging.openedRoutes.listen(_open))
          ..add(messaging.foregroundMessages.listen((_) => _refreshBell()));
      }

      if (!await messaging.requestPermission()) return;
      final token = await messaging.token();
      if (token != null) await _register(token);
    } on Object catch (error) {
      debugPrint('[push] could not start: $error');
    }
  }

  Future<void> _register(String token) async {
    if (!ref.read(sessionStateProvider).isSignedIn) return;
    try {
      await ref.read(deviceTokenRepositoryProvider).register(
            token: token,
            platform: ref.read(pushMessagingProvider).platform,
          );
      _token = token;
      state = true;
    } on Object catch (error) {
      debugPrint('[push] could not register this phone: $error');
    }
  }

  void _open(String route) {
    // Signed out, the router sends this to Welcome — which is right.
    ref.read(routerProvider).push(route);
  }

  void _refreshBell() {
    ref
      ..invalidate(notificationListProvider)
      ..invalidate(unreadNotificationCountProvider);
  }

  /// Called before signing out, while the session can still prove whose
  /// phone this is.
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await ref.read(deviceTokenRepositoryProvider).unregister(token);
    } on Object catch (error) {
      debugPrint('[push] could not release this phone: $error');
    }
    _token = null;
    state = false;
  }
}
