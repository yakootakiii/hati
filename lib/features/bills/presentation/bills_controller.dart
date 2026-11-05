import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/images/attachment_storage.dart';
import '../../../core/images/image_models.dart';
import '../../../core/split/split.dart';
import '../../groups/domain/group_models.dart';
import '../data/bills_repository.dart';
import '../domain/bill_failure.dart';
import '../domain/bill_models.dart';

part 'bills_controller.g.dart';

/// Puts members in the order the split engine expects: `joined_at`, then
/// `user_id` (spec §6.1).
///
/// The order decides who receives a leftover centavo, so the preview and the
/// server must agree on it. `canonical_participants` establishes the same order
/// server-side; this is the client half (DECISIONS D-31).
List<GroupMember> canonicalMemberOrder(List<GroupMember> members) {
  final sorted = [...members];
  sorted.sort((a, b) {
    final byJoined = (a.joinedAt ?? DateTime(0)).compareTo(
      b.joinedAt ?? DateTime(0),
    );
    return byJoined != 0 ? byJoined : a.userId.compareTo(b.userId);
  });
  return sorted;
}

@riverpod
Future<List<Bill>> groupBills(Ref ref, String groupId) =>
    ref.watch(billsRepositoryProvider).billsForGroup(groupId);

@riverpod
Future<Bill> billDetail(Ref ref, String billId) =>
    ref.watch(billsRepositoryProvider).bill(billId);

@riverpod
Future<List<GroupBalance>> myBalances(Ref ref) =>
    ref.watch(billsRepositoryProvider).myBalances();

@riverpod
Future<List<OpenShare>> myOpenShares(Ref ref) =>
    ref.watch(billsRepositoryProvider).myOpenShares();

/// Every bill mutation, with the cache invalidation in one place.
@Riverpod(keepAlive: true)
class BillActions extends _$BillActions {
  @override
  FutureOr<void> build() {}

  /// The message for the most recent failure.
  ///
  /// Read this instead of `ref` after an await: these actions invalidate the
  /// providers that built the calling widget, so the widget — and its ref —
  /// may be disposed by the time the future completes.
  String? lastError;

  /// Returns the new bill's id, or null if it failed.
  Future<String?> create(BillDraft draft) => _run(() async {
        final id = await ref.read(billsRepositoryProvider).createBill(draft);
        _refresh(draft.groupId);
        return id;
      });

  /// Creates the bill, then uploads its receipts.
  ///
  /// The bill has to exist first: receipts live at
  /// `bill-receipts/{group_id}/{bill_id}/…`, and the id is the server's to
  /// mint (DECISIONS D-36). A failed upload leaves the bill in place with
  /// fewer receipts, which is recoverable from Bill detail — losing the bill
  /// instead would not be.
  Future<String?> createWithReceipts({
    required BillDraft draft,
    required List<PickedImage> receipts,
    void Function(int done, int total)? onProgress,
  }) async {
    final id = await create(draft);
    if (id == null || receipts.isEmpty) return id;

    final uploaded = await _uploadReceipts(
      groupId: draft.groupId,
      billId: id,
      receipts: receipts,
      onProgress: onProgress,
    );
    if (uploaded == null) return null;

    return _run(() async {
      await ref
          .read(billsRepositoryProvider)
          .addAttachments(billId: id, paths: uploaded);
      ref.invalidate(billDetailProvider(id));
      return id;
    });
  }

  Future<bool> addReceipts({
    required String billId,
    required String groupId,
    required List<PickedImage> receipts,
    void Function(int done, int total)? onProgress,
  }) async {
    if (receipts.isEmpty) return true;

    final uploaded = await _uploadReceipts(
      groupId: groupId,
      billId: billId,
      receipts: receipts,
      onProgress: onProgress,
    );
    if (uploaded == null) return false;

    final result = await _run(() async {
      await ref
          .read(billsRepositoryProvider)
          .addAttachments(billId: billId, paths: uploaded);
      ref.invalidate(billDetailProvider(billId));
      return true;
    });
    return result ?? false;
  }

  Future<bool> removeAttachment({
    required String attachmentId,
    required String billId,
    required String path,
  }) async {
    final result = await _run(() async {
      await ref.read(billsRepositoryProvider).removeAttachment(attachmentId);
      ref.invalidate(billDetailProvider(billId));
      return true;
    });
    if (result != true) return false;

    // The row is the source of truth; a stranded object is untidy but
    // harmless, so a failure here does not fail the removal.
    try {
      await ref.read(attachmentStorageProvider).remove(
            bucket: StorageBucket.billReceipts,
            path: path,
          );
    } on AttachmentFailure {
      // Left for a later cleanup pass.
    }
    return true;
  }

  /// Returns the uploaded paths, or null if any upload failed.
  Future<List<String>?> _uploadReceipts({
    required String groupId,
    required String billId,
    required List<PickedImage> receipts,
    void Function(int done, int total)? onProgress,
  }) async {
    final storage = ref.read(attachmentStorageProvider);
    final paths = <String>[];

    for (var i = 0; i < receipts.length; i++) {
      final path = StoragePaths.billReceipt(
        groupId: groupId,
        billId: billId,
        filename: storage.newFilename(),
      );
      try {
        await storage.upload(
          bucket: StorageBucket.billReceipts,
          path: path,
          image: receipts[i],
        );
      } on AttachmentFailure catch (failure) {
        lastError = 'Could not upload the receipt: ${failure.message}';
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      }
      paths.add(path);
      onProgress?.call(i + 1, receipts.length);
    }
    return paths;
  }

  Future<bool> edit(String billId, BillDraft draft) async {
    final result = await _run(() async {
      await ref.read(billsRepositoryProvider).updateBill(billId, draft);
      _refresh(draft.groupId);
      ref.invalidate(billDetailProvider(billId));
      return true;
    });
    return result ?? false;
  }

  Future<bool> voidBill({
    required String billId,
    required String groupId,
    String? reason,
  }) async {
    final result = await _run(() async {
      await ref.read(billsRepositoryProvider).voidBill(billId, reason: reason);
      _refresh(groupId);
      ref.invalidate(billDetailProvider(billId));
      return true;
    });
    return result ?? false;
  }

  void _refresh(String groupId) {
    ref
      ..invalidate(groupBillsProvider(groupId))
      ..invalidate(myBalancesProvider)
      ..invalidate(myOpenSharesProvider);
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return value;
    } on BillFailure catch (failure, stackTrace) {
      lastError = failure.displayMessage;
      state = AsyncValue<void>.error(failure, stackTrace);
      return null;
    }
  }
}

String? billErrorMessage(AsyncValue<void> state) {
  final error = state.error;
  if (error == null) return null;
  if (error is BillFailure) return error.displayMessage;
  if (error is SplitException) return error.failure.slug;
  return 'Something went wrong. Try again.';
}
