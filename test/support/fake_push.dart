import 'dart:async';

import 'package:hati/core/push/push_messaging.dart';
import 'package:hati/core/push/push_registration.dart';

/// A [PushMessaging] that never touches Firebase.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({
    this.available = true,
    this.permitted = true,
    this.currentToken = 'token-1',
    this.web = false,
    this.alreadyAllowed = false,
    this.support,
  });

  bool available;
  bool permitted;
  String? currentToken;

  /// Behave like a browser: wait for a tap before asking (D-72).
  bool web;

  /// The browser already allowed notifications on an earlier visit.
  bool alreadyAllowed;

  /// Overrides [available], e.g. [PushSupport.needsHomeScreen].
  PushSupport? support;
  int permissionRequests = 0;

  final _routes = StreamController<String>.broadcast();
  final _refreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<void>.broadcast();

  void tap(String route) => _routes.add(route);
  void refresh(String token) => _refreshes.add(token);

  @override
  Future<PushSupport> initialize() async =>
      support ?? (available ? PushSupport.supported : PushSupport.unsupported);
  @override
  bool get needsUserGesture => web;
  @override
  Future<bool> hasPermission() async => alreadyAllowed;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }
  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;
  @override
  Stream<String> get openedRoutes => _routes.stream;
  @override
  Stream<void> get foregroundMessages => _foreground.stream;
  @override
  String get platform => web ? 'web' : 'android';
}

class FakeDeviceTokenRepository implements DeviceTokenRepository {
  final List<String> calls = <String>[];
  final Set<String> registered = <String>{};

  @override
  Future<void> register({
    required String token,
    required String platform,
  }) async {
    calls.add('register:$token:$platform');
    registered.add(token);
  }

  @override
  Future<void> unregister(String token) async {
    calls.add('unregister:$token');
    registered.remove(token);
  }
}
