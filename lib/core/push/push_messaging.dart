import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../platform.dart';
import 'firebase_web_options.dart';

/// Whether push can work here at all (DECISIONS D-65, D-72).
enum PushSupport {
  supported,

  /// No Firebase config, or a browser without push.
  unsupported,

  /// Safari on an iPhone: push only works once Hati is added to the Home
  /// Screen (iOS 16.4+).
  needsHomeScreen,
}

/// The phone side of push notifications (DECISIONS D-65), behind an interface
/// so tests — and builds with no Firebase project yet — never touch Firebase.
abstract interface class PushMessaging {
  Future<PushSupport> initialize();

  /// Browsers only let a page ask for notifications from a tap, so on the
  /// web Hati waits for the user to turn them on (D-72).
  bool get needsUserGesture;

  /// Notifications are already allowed — no need to ask.
  Future<bool> hasPermission();

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
  Future<PushSupport> initialize() async {
    if (_ready) return PushSupport.supported;

    if (kIsWeb) {
      // The web app (D-72): needs the VAPID key and a browser with push.
      if (kFirebaseVapidKey.isEmpty) return PushSupport.unsupported;
      try {
        await Firebase.initializeApp(options: kFirebaseWebOptions);
        if (!await FirebaseMessaging.instance.isSupported()) {
          return AppPlatform.isIOSDevice
              ? PushSupport.needsHomeScreen
              : PushSupport.unsupported;
        }
      } on Object catch (error) {
        debugPrint('[push] web push unavailable: $error');
        return PushSupport.unsupported;
      }
      FirebaseMessaging.onMessageOpenedApp.listen(_emitRoute);
      _ready = true;
      return PushSupport.supported;
    }

    if (!(AppPlatform.isAndroidApp || AppPlatform.isIOSApp)) {
      return PushSupport.unsupported;
    }
    try {
      await Firebase.initializeApp();
    } on Object catch (error) {
      // Expected until the Firebase project is set up (D-65).
      debugPrint('[push] Firebase is not configured: $error');
      return PushSupport.unsupported;
    }

    FirebaseMessaging.onMessageOpenedApp.listen(_emitRoute);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // After listeners attach, so the launch tap is not lost.
      scheduleMicrotask(() => _emitRoute(initial));
    }
    _ready = true;
    return PushSupport.supported;
  }

  @override
  bool get needsUserGesture => kIsWeb;

  @override
  Future<bool> hasPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
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
  Future<String?> token() => FirebaseMessaging.instance.getToken(
        // The web needs the VAPID key to subscribe this browser (D-72).
        vapidKey: kIsWeb ? kFirebaseVapidKey : null,
      );

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<String> get openedRoutes => _opened.stream;

  @override
  Stream<void> get foregroundMessages => FirebaseMessaging.onMessage;

  @override
  String get platform => kIsWeb
      ? 'web'
      : AppPlatform.isIOSApp
          ? 'ios'
          : 'android';
}

/// Push switched off: what tests use, and the fallback when Firebase is not
/// available.
class DisabledPushMessaging implements PushMessaging {
  const DisabledPushMessaging();

  @override
  Future<PushSupport> initialize() async => PushSupport.unsupported;
  @override
  bool get needsUserGesture => false;
  @override
  Future<bool> hasPermission() async => false;
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
