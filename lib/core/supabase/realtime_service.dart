import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

part 'realtime_service.g.dart';

/// A live subscription that must be closed when the screen goes away.
abstract interface class RealtimeHandle {
  Future<void> close();
}

/// Postgres Changes, scoped to one screen (spec §4.3).
///
/// An interface so widget tests can drive the same code paths without a socket.
abstract interface class RealtimeService {
  /// Watches the tables the Group detail screen shows.
  RealtimeHandle watchGroup({
    required String groupId,
    required VoidCallback onChange,
  });

  /// Watches the tables the Bill detail screen shows.
  RealtimeHandle watchBill({
    required String billId,
    required VoidCallback onChange,
  });
}

class _ChannelHandle implements RealtimeHandle {
  _ChannelHandle(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> close() => _client.removeChannel(_channel);
}

class SupabaseRealtimeService implements RealtimeService {
  SupabaseRealtimeService(this._client);

  final SupabaseClient _client;

  @override
  RealtimeHandle watchGroup({
    required String groupId,
    required VoidCallback onChange,
  }) {
    // bills and activity_events carry group_id, so they filter server-side.
    // bill_shares does not, so it is watched unfiltered and the callback
    // simply refetches — the alternative is a filter per open bill, which
    // costs more than the occasional extra refresh.
    final channel = _client.channel('group:$groupId');

    for (final table in const ['bills', 'activity_events']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: groupId,
        ),
        callback: (_) => onChange(),
      );
    }
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bill_shares',
      callback: (_) => onChange(),
    );

    channel.subscribe();
    return _ChannelHandle(_client, channel);
  }

  @override
  RealtimeHandle watchBill({
    required String billId,
    required VoidCallback onChange,
  }) {
    final channel = _client.channel('bill:$billId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'bill_id',
        value: billId,
      ),
      callback: (_) => onChange(),
    );
    // Shares and payments have no bill_id column to filter on; RLS still
    // decides what the subscriber is allowed to be told about.
    for (final table in const ['bill_shares', 'payments']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => onChange(),
      );
    }

    channel.subscribe();
    return _ChannelHandle(_client, channel);
  }
}

/// A service that does nothing, for builds with no project attached.
class InertRealtimeService implements RealtimeService {
  const InertRealtimeService();

  @override
  RealtimeHandle watchGroup({
    required String groupId,
    required VoidCallback onChange,
  }) =>
      const _NoopHandle();

  @override
  RealtimeHandle watchBill({
    required String billId,
    required VoidCallback onChange,
  }) =>
      const _NoopHandle();
}

class _NoopHandle implements RealtimeHandle {
  const _NoopHandle();

  @override
  Future<void> close() async {}
}

@Riverpod(keepAlive: true)
RealtimeService realtimeService(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    return const InertRealtimeService();
  }
  return SupabaseRealtimeService(Supabase.instance.client);
}
