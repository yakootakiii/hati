import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The phone side of push notifications (DECISIONS D-65), behind an interface
/// so tests — and builds with no Firebase project yet — never touch Firebase.
abstract interface class PushMessaging {
  /// False when push cannot work on this build or device: no
  /// google-services.json yet, or a platform without Firebase.
  Future<bool> initialize();

  /// Asks to show notifications (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// The in-app route of each notification the user taps — including the
  /// one that launched the app.
  Stream<String> get openedRoutes;

  /// Fires when a push arrives while Hati is open.
  Stream<void> get foregroundMessages;

  String get platform;
}

class FirebasePushMessaging implements PushMessaging {
  final _opened = StreamController<String>.broadcast();
  bool _ready = false;

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      await Firebase.initializeApp();
    } on Object catch (error) {
      // Expected until the Firebase project is set up (D-65).
      debugPrint('[push] Firebase is not configured: $error');
      return false;
    }

    FirebaseMessaging.onMessageOpenedApp.listen(_emitRoute);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // After listeners attach, so the launch tap is not lost.
      scheduleMicrotask(() => _emitRoute(initial));
    }
    _ready = true;
    return true;
  }

  void _emitRoute(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.startsWith('/')) _opened.add(route);
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // The classic FCM registration token, on purpose: send-push addresses
  // messages with HTTP v1 `message.token`, which takes exactly this. The
  // newer register()/onRegistered flow yields an installation ID for a
  // different send path (DECISIONS D-65).
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<String> get openedRoutes => _opened.stream;

  @override
  Stream<void> get foregroundMessages => FirebaseMessaging.onMessage;

  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';
}

/// Push switched off: what tests use, and the fallback when Firebase is not
/// available.
class DisabledPushMessaging implements PushMessaging {
  const DisabledPushMessaging();

  @override
  Future<bool> initialize() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<String> get openedRoutes => const Stream.empty();
  @override
  Stream<void> get foregroundMessages => const Stream.empty();
  @override
  String get platform => 'android';
}
