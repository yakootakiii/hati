import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a stream to [Listenable], which is what go_router's
/// `refreshListenable` expects.
///
/// Using this instead of watching a provider means an auth event re-runs the
/// redirect without rebuilding the router itself, so navigation state survives.
class StreamListenable extends ChangeNotifier {
  StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
