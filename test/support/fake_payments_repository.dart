import 'package:hati/features/settlements/data/payments_repository.dart';
import 'package:hati/features/settlements/domain/payment.dart';
import 'package:hati/features/settlements/domain/settlement_failure.dart';

/// An in-memory [PaymentsRepository] for tests.
///
/// Mirrors the RPC's idempotency (spec §12.9): marking a share paid twice
/// returns the same payment.
class FakePaymentsRepository implements PaymentsRepository {
  FakePaymentsRepository({List<Payment>? payments})
    : payments = payments ?? <Payment>[];

  final List<Payment> payments;

  SettlementFailure? failWith;
  final List<String> calls = <String>[];
  Map<String, Object?> lastArgs = <String, Object?>{};

  @override
  Future<String> markPaid({
    required String billShareId,
    String? method,
    String? referenceNo,
    String? proofPath,
  }) async {
    calls.add('markPaid');
    lastArgs = {
      'billShareId': billShareId,
      'method': method,
      'referenceNo': referenceNo,
      'proofPath': proofPath,
    };
    _maybeFail();

    // Mirrors HT047: the RPC refuses a claim with no screenshot — except
    // cash, which has none (D-70).
    if (method != 'cash' && (proofPath == null || proofPath.trim().isEmpty)) {
      throw const SettlementFailure(
        SettlementFailureKind.proofRequired,
        'Attach a screenshot of your payment',
      );
    }

    final existing = payments
        .where((p) => p.billShareId == billShareId && p.isPending)
        .firstOrNull;
    return existing?.id ?? 'payment-${payments.length + 1}';
  }

  @override
  Future<String> markPaidBatch({
    required List<String> billShareIds,
    String? method,
    String? referenceNo,
    String? proofPath,
  }) async {
    calls.add('markPaidBatch');
    lastArgs = {
      'billShareIds': billShareIds,
      'method': method,
      'referenceNo': referenceNo,
      'proofPath': proofPath,
    };
    _maybeFail();
    return 'batch-1';
  }

  @override
  Future<void> confirmBatch(String batchId) async {
    calls.add('confirmBatch');
    lastArgs = {'batchId': batchId};
    _maybeFail();
  }

  @override
  Future<void> rejectBatch(String batchId, {String? reason}) async {
    calls.add('rejectBatch');
    lastArgs = {'batchId': batchId, 'reason': reason};
    _maybeFail();
  }

  @override
  Future<List<Payment>> forBatch(String batchId) async {
    calls.add('forBatch');
    _maybeFail();
    return payments.where((p) => p.batchId == batchId).toList();
  }

  @override
  Future<void> confirm(String paymentId) async {
    calls.add('confirm');
    lastArgs = {'paymentId': paymentId};
    _maybeFail();
  }

  @override
  Future<void> reject(String paymentId, {String? reason}) async {
    calls.add('reject');
    lastArgs = {'paymentId': paymentId, 'reason': reason};
    _maybeFail();
  }

  @override
  Future<String> recordReceived({
    required String billShareId,
    String method = 'cash',
  }) async {
    calls.add('recordReceived');
    lastArgs = {'billShareId': billShareId, 'method': method};
    _maybeFail();
    return 'cash-payment';
  }

  @override
  Future<List<Payment>> forBill(String billId) async {
    calls.add('forBill');
    _maybeFail();
    return payments;
  }

  @override
  Future<void> setReceiveMethod({
    required String billId,
    String? methodId,
  }) async {
    calls.add('setReceiveMethod');
    lastArgs = {'billId': billId, 'methodId': methodId};
    _maybeFail();
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
