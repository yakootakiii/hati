import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/money/money.dart';
import '../../../core/split/split.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/recurring_bill.dart';

part 'recurring_repository.g.dart';

enum RecurringFailureKind {
  notFound,
  notAllowed,
  invalidRecurrence,
  payerNotMember,
  splitInvalid,
  invalidInput,
  network,
  unknown,
}

class RecurringFailure implements Exception {
  const RecurringFailure(this.kind, this.message);

  final RecurringFailureKind kind;
  final String message;

  factory RecurringFailure.fromCode(String? code, String message) {
    // The split engine's own range comes through untouched (D-30).
    if (code != null && code.startsWith('HT02')) {
      return RecurringFailure(RecurringFailureKind.splitInvalid, message);
    }
    final kind = switch (code) {
      'HT001' || 'HT002' => RecurringFailureKind.notAllowed,
      'HT010' => RecurringFailureKind.invalidInput,
      'HT031' => RecurringFailureKind.payerNotMember,
      'HT060' => RecurringFailureKind.notFound,
      'HT061' => RecurringFailureKind.notAllowed,
      'HT062' => RecurringFailureKind.invalidRecurrence,
      _ => RecurringFailureKind.unknown,
    };
    return RecurringFailure(kind, message);
  }

  String get displayMessage => switch (kind) {
        RecurringFailureKind.notFound => 'That repeating bill no longer exists.',
        RecurringFailureKind.splitInvalid =>
          "The split doesn't add up. Check the amounts.",
        RecurringFailureKind.network =>
          "Can't reach Hati right now. Check your connection and try again.",
        RecurringFailureKind.unknown => 'Something went wrong. Try again.',
        _ => message,
      };

  @override
  String toString() => 'RecurringFailure(${kind.name}): $message';
}

/// Everything the Recurring bills screen does (spec §10).
class RecurringDraft {
  const RecurringDraft({
    required this.groupId,
    required this.title,
    required this.total,
    required this.paidBy,
    required this.mode,
    required this.participants,
    required this.frequency,
    required this.nextRunOn,
    this.interval = 1,
    this.anchorDay,
    this.endsOn,
    this.category,
    this.notes,
  });

  final String groupId;
  final String title;
  final Money total;
  final String paidBy;
  final SplitMode mode;
  final List<SplitParticipant> participants;
  final RecurrenceFrequency frequency;
  final DateTime nextRunOn;
  final int interval;
  final int? anchorDay;
  final DateTime? endsOn;
  final String? category;
  final String? notes;

  static String _date(DateTime value) =>
      value.toIso8601String().split('T').first;

  Map<String, dynamic> toPayload() => {
        'group_id': groupId,
        'title': title,
        'total_amount': total.centavos,
        'paid_by': paidBy,
        'split_mode': mode.name,
        'frequency': frequency.wire,
        'interval': interval,
        'next_run_on': _date(nextRunOn),
        if (anchorDay != null) 'anchor_day': anchorDay,
        if (endsOn != null) 'ends_on': _date(endsOn!),
        if (category != null && category!.isNotEmpty) 'category': category,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'participants': [
          for (final p in participants)
            {'user_id': p.userId, if (p.input != null) 'input': p.input},
        ],
      };

  /// The same request the preview runs, so the form can show what each person
  /// will owe before the first run.
  SplitRequest toSplitRequest() => SplitRequest(
        total: total,
        mode: mode,
        participants: participants,
      );
}

abstract interface class RecurringRepository {
  Future<List<RecurringBill>> forGroup(String groupId);

  Future<String> create(RecurringDraft draft);

  Future<void> update(String templateId, RecurringDraft draft);

  Future<void> setPaused({required String templateId, required bool paused});

  Future<void> remove(String templateId);
}

class SupabaseRecurringRepository implements RecurringRepository {
  SupabaseRecurringRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RecurringBill>> forGroup(String groupId) {
    return _guard(() async {
      final rows = await _client
          .from('recurring_bills')
          .select()
          .eq('group_id', groupId)
          .order('paused')
          .order('next_run_on');

      return rows.map((row) {
        final config = row['split_config'] as Map<String, dynamic>?;
        final participants =
            (config?['participants'] as List<dynamic>?) ?? const [];
        return RecurringBill(
          id: row['id'] as String,
          groupId: row['group_id'] as String,
          createdBy: row['created_by'] as String?,
          title: row['title'] as String,
          category: row['category'] as String?,
          notes: row['notes'] as String?,
          totalAmount: Money((row['total_amount'] as num).toInt()),
          paidBy: row['paid_by'] as String,
          splitMode: row['split_mode'] as String,
          frequency: row['frequency'] as String,
          interval: (row['interval'] as num?)?.toInt() ?? 1,
          anchorDay: (row['anchor_day'] as num?)?.toInt(),
          nextRunOn: DateTime.parse(row['next_run_on'] as String),
          endsOn: row['ends_on'] == null
              ? null
              : DateTime.parse(row['ends_on'] as String),
          paused: row['paused'] as bool? ?? false,
          participantIds: [
            for (final p in participants.cast<Map<String, dynamic>>())
              p['user_id'] as String,
          ],
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<String> create(RecurringDraft draft) => _guard(
        () => _client.rpc<String>(
          'create_recurring_bill',
          params: {'p_payload': draft.toPayload()},
        ),
      );

  @override
  Future<void> update(String templateId, RecurringDraft draft) => _guard(
        () => _client.rpc<void>(
          'update_recurring_bill',
          params: {
            'p_template_id': templateId,
            'p_payload': draft.toPayload(),
          },
        ),
      );

  @override
  Future<void> setPaused({
    required String templateId,
    required bool paused,
  }) =>
      _guard(
        () => _client.rpc<void>(
          'set_recurring_paused',
          params: {'p_template_id': templateId, 'p_paused': paused},
        ),
      );

  @override
  Future<void> remove(String templateId) => _guard(
        () => _client.rpc<void>(
          'delete_recurring_bill',
          params: {'p_template_id': templateId},
        ),
      );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw RecurringFailure.fromCode(error.code, error.message);
    } on SocketException catch (_) {
      throw const RecurringFailure(
        RecurringFailureKind.network,
        "Can't reach Hati right now.",
      );
    }
  }
}

@Riverpod(keepAlive: true)
RecurringRepository recurringRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Recurring bills need a Supabase project.');
  }
  return SupabaseRecurringRepository(Supabase.instance.client);
}
