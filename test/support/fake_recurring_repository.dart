import 'package:hati/features/recurring/data/recurring_repository.dart';
import 'package:hati/features/recurring/domain/recurring_bill.dart';

/// An in-memory [RecurringRepository] for tests.
class FakeRecurringRepository implements RecurringRepository {
  FakeRecurringRepository({List<RecurringBill>? templates})
    : templates = templates ?? <RecurringBill>[];

  final List<RecurringBill> templates;

  /// Fails the next call to any method.
  RecurringFailure? failWith;

  /// Fails only [create] and [update]. Separate because the form loads the
  /// template list first, which would otherwise swallow a general `failWith`.
  RecurringFailure? saveFailure;
  final List<String> calls = <String>[];
  Map<String, Object?> lastArgs = <String, Object?>{};
  RecurringDraft? lastDraft;

  @override
  Future<List<RecurringBill>> forGroup(String groupId) async {
    calls.add('forGroup');
    _maybeFail();
    return templates.where((t) => t.groupId == groupId).toList();
  }

  @override
  Future<String> create(RecurringDraft draft) async {
    calls.add('create');
    lastDraft = draft;
    _maybeFailSave();
    _maybeFail();
    return 'new-template-id';
  }

  @override
  Future<void> update(String templateId, RecurringDraft draft) async {
    calls.add('update');
    lastArgs = {'templateId': templateId};
    lastDraft = draft;
    _maybeFailSave();
    _maybeFail();
  }

  @override
  Future<void> setPaused({
    required String templateId,
    required bool paused,
  }) async {
    calls.add('setPaused');
    lastArgs = {'templateId': templateId, 'paused': paused};
    _maybeFail();
  }

  @override
  Future<void> remove(String templateId) async {
    calls.add('remove');
    lastArgs = {'templateId': templateId};
    _maybeFail();
  }

  void _maybeFailSave() {
    final failure = saveFailure;
    if (failure != null) {
      saveFailure = null;
      throw failure;
    }
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
