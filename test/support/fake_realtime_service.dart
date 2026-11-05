import 'package:flutter/foundation.dart';
import 'package:hati/core/supabase/realtime_service.dart';

/// A [RealtimeService] that records what was watched and lets a test fire a
/// change by hand.
class FakeRealtimeService implements RealtimeService {
  final List<String> watching = <String>[];
  final List<String> closed = <String>[];
  final Map<String, VoidCallback> _callbacks = {};

  @override
  RealtimeHandle watchGroup({
    required String groupId,
    required VoidCallback onChange,
  }) => _register('group:$groupId', onChange);

  @override
  RealtimeHandle watchBill({
    required String billId,
    required VoidCallback onChange,
  }) => _register('bill:$billId', onChange);

  RealtimeHandle _register(String key, VoidCallback onChange) {
    watching.add(key);
    _callbacks[key] = onChange;
    return _FakeHandle(this, key);
  }

  /// Simulates a Postgres change arriving for a subscription.
  void fire(String key) => _callbacks[key]?.call();

  bool isOpen(String key) => _callbacks.containsKey(key);
}

class _FakeHandle implements RealtimeHandle {
  _FakeHandle(this._service, this._key);

  final FakeRealtimeService _service;
  final String _key;

  @override
  Future<void> close() async {
    _service.closed.add(_key);
    _service._callbacks.remove(_key);
  }
}
