import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/supabase/realtime_service.dart';
import '../../bills/presentation/bills_controller.dart';
import '../data/activity_repository.dart';
import '../domain/activity_event.dart';
import '../domain/comment.dart';

part 'activity_controller.g.dart';

/// One page of a feed. [groupId] null means the merged feed.
@riverpod
Future<List<ActivityEvent>> activityFeed(Ref ref, {String? groupId}) =>
    ref.watch(activityRepositoryProvider).feed(groupId: groupId);

@riverpod
Future<List<Comment>> billComments(Ref ref, String billId) =>
    ref.watch(activityRepositoryProvider).comments(billId);

/// Loads older pages on demand, keeping what is already on screen.
@riverpod
class ActivityPager extends _$ActivityPager {
  @override
  FutureOr<List<ActivityEvent>> build({String? groupId}) =>
      ref.watch(activityRepositoryProvider).feed(groupId: groupId);

  bool _exhausted = false;
  bool _loading = false;

  bool get hasMore => !_exhausted;

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.isEmpty || _exhausted || _loading) return;

    _loading = true;
    try {
      final older = await ref.read(activityRepositoryProvider).feed(
            groupId: groupId,
            before: current.last.createdAt,
          );
      if (older.isEmpty) {
        _exhausted = true;
      } else {
        state = AsyncValue.data([...current, ...older]);
      }
    } on ActivityFailure {
      // The list keeps what it has; the user can pull to refresh.
      _exhausted = true;
    } finally {
      _loading = false;
    }
  }
}

@riverpod
class CommentActions extends _$CommentActions {
  @override
  FutureOr<void> build() {}

  String? lastError;

  Future<bool> add({required String billId, required String body}) =>
      _run(billId, () => ref
          .read(activityRepositoryProvider)
          .addComment(billId: billId, body: body));

  Future<bool> edit({
    required String billId,
    required String commentId,
    required String body,
  }) =>
      _run(billId, () => ref
          .read(activityRepositoryProvider)
          .editComment(commentId: commentId, body: body));

  Future<bool> remove({required String billId, required String commentId}) =>
      _run(billId,
          () => ref.read(activityRepositoryProvider).deleteComment(commentId));

  Future<bool> _run(String billId, Future<void> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      ref.invalidate(billCommentsProvider(billId));
      // A comment emits an activity event through a trigger, so the feeds are
      // stale too.
      ref.invalidate(activityPagerProvider);
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return true;
    } on ActivityFailure catch (failure, stackTrace) {
      lastError = failure.message;
      state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}

/// Keeps Group detail fresh while it is open (spec §4.3).
///
/// Watched by the screen, so the subscription lives exactly as long as the
/// screen does — autoDispose closes the channel when it goes away.
@riverpod
void groupRealtime(Ref ref, String groupId) {
  final handle = ref.watch(realtimeServiceProvider).watchGroup(
        groupId: groupId,
        onChange: () {
          ref
            ..invalidate(groupBillsProvider(groupId))
            ..invalidate(activityPagerProvider(groupId: groupId))
            ..invalidate(myBalancesProvider)
            ..invalidate(myOpenSharesProvider);
        },
      );
  ref.onDispose(handle.close);
}

/// Keeps Bill detail fresh while it is open (spec §4.3).
@riverpod
void billRealtime(Ref ref, String billId) {
  final handle = ref.watch(realtimeServiceProvider).watchBill(
        billId: billId,
        onChange: () {
          ref
            ..invalidate(billDetailProvider(billId))
            ..invalidate(billCommentsProvider(billId))
            ..invalidate(myOpenSharesProvider);
        },
      );
  ref.onDispose(handle.close);
}
