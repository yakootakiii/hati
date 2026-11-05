import 'dart:async';

import 'package:hati/core/push/push_messaging.dart';
import 'package:hati/core/push/push_registration.dart';

/// A [PushMessaging] that never touches Firebase.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({
    this.available = true,
    this.permitted = true,
    this.currentToken = 'token-1',
  });

  bool available;
  bool permitted;
  String? currentToken;

  final _routes = StreamController<String>.broadcast();
  final _refreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<void>.broadcast();

  void tap(String route) => _routes.add(route);
  void refresh(String token) => _refreshes.add(token);

  @override
  Future<bool> initialize() async => available;
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;
  @override
  Stream<String> get openedRoutes => _routes.stream;
  @override
  Stream<void> get foregroundMessages => _foreground.stream;
  @override
  String get platform => 'android';
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
