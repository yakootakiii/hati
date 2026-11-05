import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/money/money.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/payment.dart';
import '../domain/settlement_failure.dart';

part 'payments_repository.g.dart';

/// Settlement (spec §7, §9).
///
/// Payments are never written directly — each call goes through the RPC that
/// enforces who may do it and what the current status allows.
abstract interface class PaymentsRepository {
  /// Marks the caller's share paid. Returns the payment id; calling twice
  /// returns the same one (spec §12.9).
  Future<String> markPaid({
    required String billShareId,
    String? method,
    String? referenceNo,
    String? proofPath,
  });

  Future<void> confirm(String paymentId);

  Future<void> reject(String paymentId, {String? reason});

  /// One payment for several of the caller's shares, all owed to one person
  /// in one group. Returns the batch id (DECISIONS D-67).
  Future<String> markPaidBatch({
    required List<String> billShareIds,
    String? method,
    String? referenceNo,
    String? proofPath,
  });

  /// Every payment in a batch at once.
  Future<void> confirmBatch(String batchId);

  Future<void> rejectBatch(String batchId, {String? reason});

  /// The payments that make up a batch.
  Future<List<Payment>> forBatch(String batchId);

  /// The payer records cash handed over in person.
  Future<String> recordReceived({
    required String billShareId,
    String method = 'cash',
  });

  /// Payments on a bill, newest first — the payer's review list.
  Future<List<Payment>> forBill(String billId);

  /// The payer picks which of their payment methods debtors should pay into,
  /// or null for any of them.
  Future<void> setReceiveMethod({
    required String billId,
    String? methodId,
  });
}

class SupabasePaymentsRepository implements PaymentsRepository {
  SupabasePaymentsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> markPaid({
    required String billShareId,
    String? method,
    String? referenceNo,
    String? proofPath,
  }) {
    return _guard(
      () => _client.rpc<String>(
        'mark_share_paid',
        params: {
          'p_bill_share_id': billShareId,
          'p_method': method,
          'p_reference_no': referenceNo,
          'p_proof_path': proofPath,
        },
      ),
    );
  }

  @override
  Future<String> markPaidBatch({
    required List<String> billShareIds,
    String? method,
    String? referenceNo,
    String? proofPath,
  }) {
    return _guard(
      () => _client.rpc<String>(
        'mark_shares_paid',
        params: {
          'p_share_ids': billShareIds,
          'p_method': method,
          'p_reference_no': referenceNo,
          'p_proof_path': proofPath,
        },
      ),
    );
  }

  @override
  Future<void> confirmBatch(String batchId) => _guard(
        () => _client.rpc<void>(
          'confirm_payment_batch',
          params: {'p_batch_id': batchId},
        ),
      );

  @override
  Future<void> rejectBatch(String batchId, {String? reason}) => _guard(
        () => _client.rpc<void>(
          'reject_payment_batch',
          params: {'p_batch_id': batchId, 'p_reason': reason},
        ),
      );

  @override
  Future<List<Payment>> forBatch(String batchId) {
    return _guard(() async {
      final rows = await _client
          .from('payments')
          .select(_paymentColumns)
          .eq('batch_id', batchId)
          .order('created_at');
      return rows.map(_toPayment).toList(growable: false);
    });
  }

  @override
  Future<void> confirm(String paymentId) => _guard(
        () => _client.rpc<void>(
          'confirm_payment',
          params: {'p_payment_id': paymentId},
        ),
      );

  @override
  Future<void> reject(String paymentId, {String? reason}) => _guard(
        () => _client.rpc<void>(
          'reject_payment',
          params: {'p_payment_id': paymentId, 'p_reason': reason},
        ),
      );

  @override
  Future<String> recordReceived({
    required String billShareId,
    String method = 'cash',
  }) {
    return _guard(
      () => _client.rpc<String>(
        'record_payment_received',
        params: {'p_bill_share_id': billShareId, 'p_method': method},
      ),
    );
  }

  @override
  Future<void> setReceiveMethod({
    required String billId,
    String? methodId,
  }) =>
      _guard(
        () => _client.rpc<void>(
          'set_bill_receive_method',
          params: {'p_bill_id': billId, 'p_method_id': methodId},
        ),
      );

  static const String _paymentColumns =
      'id, bill_share_id, from_user, to_user, amount, method, '
      'reference_no, proof_path, status, rejected_reason, confirmed_at, '
      'created_at, batch_id';

  @override
  Future<List<Payment>> forBill(String billId) {
    return _guard(() async {
      final rows = await _client
          .from('payments')
          .select('$_paymentColumns, bill_shares!inner(bill_id)')
          .eq('bill_shares.bill_id', billId)
          .order('created_at', ascending: false);

      return rows.map(_toPayment).toList(growable: false);
    });
  }

  static Payment _toPayment(Map<String, dynamic> row) => Payment(
        id: row['id'] as String,
        billShareId: row['bill_share_id'] as String,
        fromUser: row['from_user'] as String,
        toUser: row['to_user'] as String,
        amount: Money((row['amount'] as num).toInt()),
        method: row['method'] as String?,
        referenceNo: row['reference_no'] as String?,
        proofPath: row['proof_path'] as String?,
        status: row['status'] as String,
        rejectedReason: row['rejected_reason'] as String?,
        confirmedAt: DateTime.tryParse(row['confirmed_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
        batchId: row['batch_id'] as String?,
      );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw SettlementFailure.fromCode(error.code, error.message);
    } on SocketException catch (_) {
      throw const SettlementFailure(
        SettlementFailureKind.network,
        "Can't reach Hati right now.",
      );
    }
  }
}

@Riverpod(keepAlive: true)
PaymentsRepository paymentsRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError('Settlement needs a Supabase project.');
  }
  return SupabasePaymentsRepository(Supabase.instance.client);
}
