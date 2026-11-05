import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/images/attachment_storage.dart';
import '../../../core/images/image_models.dart';
import '../../bills/presentation/bills_controller.dart';
import '../data/payments_repository.dart';
import '../domain/payment.dart';
import '../domain/settlement_failure.dart';

part 'settlements_controller.g.dart';

@riverpod
Future<List<Payment>> billPayments(Ref ref, String billId) =>
    ref.watch(paymentsRepositoryProvider).forBill(billId);

/// Every payment that one transfer covered (DECISIONS D-67).
@riverpod
Future<List<Payment>> batchPayments(Ref ref, String batchId) =>
    ref.watch(paymentsRepositoryProvider).forBatch(batchId);

/// Every settlement action, with the cache invalidation in one place.
@Riverpod(keepAlive: true)
class SettlementActions extends _$SettlementActions {
  @override
  FutureOr<void> build() {}

  /// The message for the most recent failure.
  ///
  /// Read this instead of `ref` after an await: these actions invalidate the
  /// providers that built the calling widget, so the widget — and its ref —
  /// may be disposed by the time the future completes.
  String? lastError;

  /// Marks the caller's share paid, uploading the proof screenshot first —
  /// the path has to exist before the RPC records it. The RPC refuses a claim
  /// without one (HT047), except for cash (D-70).
  Future<bool> markPaid({
    required String billShareId,
    required String billId,
    required String groupId,
    PickedImage? proof,
    String? method,
    String? referenceNo,
  }) async {
    final proofPath = await _uploadProof(groupId, proof);
    if (proof != null && proofPath == null) return false;

    return _run(billId, groupId, () async {
      await ref.read(paymentsRepositoryProvider).markPaid(
            billShareId: billShareId,
            method: method,
            referenceNo: referenceNo,
            proofPath: proofPath,
          );
    });
  }

  /// One payment for several shares in one group (DECISIONS D-67). Uploads
  /// the single screenshot first, as for one bill.
  Future<bool> markPaidBatch({
    required List<String> billShareIds,
    required List<String> billIds,
    required String groupId,
    PickedImage? proof,
    String? method,
    String? referenceNo,
  }) async {
    final proofPath = await _uploadProof(groupId, proof);
    if (proof != null && proofPath == null) return false;

    return _runMany(billIds, groupId, () async {
      await ref.read(paymentsRepositoryProvider).markPaidBatch(
            billShareIds: billShareIds,
            method: method,
            referenceNo: referenceNo,
            proofPath: proofPath,
          );
    });
  }

  /// Uploads [proof] into the group's proofs folder and returns its path, or
  /// null — when there is no proof, or the upload failed (then [lastError] is
  /// set).
  Future<String?> _uploadProof(String groupId, PickedImage? proof) async {
    if (proof == null) return null;
    final storage = ref.read(attachmentStorageProvider);
    final path = StoragePaths.paymentProof(
      groupId: groupId,
      filename: storage.newFilename(),
    );
    try {
      await storage.upload(
        bucket: StorageBucket.paymentProofs,
        path: path,
        image: proof,
      );
      return path;
    } on AttachmentFailure catch (failure, stackTrace) {
      lastError = 'Could not upload the screenshot: ${failure.message}';
      state = AsyncValue<void>.error(failure, stackTrace);
      return null;
    }
  }

  Future<bool> confirmBatch({
    required String batchId,
    required List<String> billIds,
    required String groupId,
  }) =>
      _runMany(billIds, groupId,
          () => ref.read(paymentsRepositoryProvider).confirmBatch(batchId));

  Future<bool> rejectBatch({
    required String batchId,
    required List<String> billIds,
    required String groupId,
    String? reason,
  }) =>
      _runMany(
        billIds,
        groupId,
        () => ref
            .read(paymentsRepositoryProvider)
            .rejectBatch(batchId, reason: reason),
      );

  Future<bool> confirm({
    required String paymentId,
    required String billId,
    required String groupId,
  }) =>
      _run(billId, groupId,
          () => ref.read(paymentsRepositoryProvider).confirm(paymentId));

  Future<bool> reject({
    required String paymentId,
    required String billId,
    required String groupId,
    String? reason,
  }) =>
      _run(
        billId,
        groupId,
        () => ref
            .read(paymentsRepositoryProvider)
            .reject(paymentId, reason: reason),
      );

  /// The payer chooses where debtors should pay them on this bill; null means
  /// any of their payment methods.
  Future<bool> setReceiveMethod({
    required String billId,
    required String groupId,
    String? methodId,
  }) =>
      _run(
        billId,
        groupId,
        () => ref
            .read(paymentsRepositoryProvider)
            .setReceiveMethod(billId: billId, methodId: methodId),
      );

  Future<bool> recordCash({
    required String billShareId,
    required String billId,
    required String groupId,
  }) =>
      _run(billId, groupId, () async {
        await ref
            .read(paymentsRepositoryProvider)
            .recordReceived(billShareId: billShareId);
      });

  Future<bool> _run(
    String billId,
    String groupId,
    Future<void> Function() action,
  ) =>
      _runMany([billId], groupId, action);

  Future<bool> _runMany(
    List<String> billIds,
    String groupId,
    Future<void> Function() action,
  ) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      for (final billId in billIds) {
        ref
          ..invalidate(billDetailProvider(billId))
          ..invalidate(billPaymentsProvider(billId));
      }
      ref
        ..invalidate(groupBillsProvider(groupId))
        ..invalidate(myBalancesProvider)
        ..invalidate(myOpenSharesProvider);
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return true;
    } on SettlementFailure catch (failure, stackTrace) {
      lastError = failure.displayMessage;
      state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}

String? settlementErrorMessage(AsyncValue<void> state) {
  final error = state.error;
  if (error == null) return null;
  if (error is SettlementFailure) return error.displayMessage;
  return 'Something went wrong. Try again.';
}
