import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../bills/presentation/bills_controller.dart';
import '../data/recurring_repository.dart';
import '../domain/recurring_bill.dart';

part 'recurring_controller.g.dart';

@riverpod
Future<List<RecurringBill>> groupRecurringBills(Ref ref, String groupId) =>
    ref.watch(recurringRepositoryProvider).forGroup(groupId);

@Riverpod(keepAlive: true)
class RecurringActions extends _$RecurringActions {
  @override
  FutureOr<void> build() {}

  String? lastError;

  Future<String?> create(RecurringDraft draft) async {
    final result = await _run(draft.groupId, () async {
      return ref.read(recurringRepositoryProvider).create(draft);
    });
    return result;
  }

  Future<bool> edit(String templateId, RecurringDraft draft) async {
    final result = await _run(draft.groupId, () async {
      await ref.read(recurringRepositoryProvider).update(templateId, draft);
      return true;
    });
    return result ?? false;
  }

  Future<bool> setPaused({
    required String templateId,
    required String groupId,
    required bool paused,
  }) async {
    final result = await _run(groupId, () async {
      await ref
          .read(recurringRepositoryProvider)
          .setPaused(templateId: templateId, paused: paused);
      return true;
    });
    return result ?? false;
  }

  Future<bool> remove({
    required String templateId,
    required String groupId,
  }) async {
    final result = await _run(groupId, () async {
      await ref.read(recurringRepositoryProvider).remove(templateId);
      return true;
    });
    return result ?? false;
  }

  Future<T?> _run<T>(String groupId, Future<T> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      ref
        ..invalidate(groupRecurringBillsProvider(groupId))
        // A template can generate a bill the moment it is due, so the group's
        // bills may be stale too.
        ..invalidate(groupBillsProvider(groupId));
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return value;
    } on RecurringFailure catch (failure, stackTrace) {
      lastError = failure.displayMessage;
      state = AsyncValue<void>.error(failure, stackTrace);
      return null;
    }
  }
}
