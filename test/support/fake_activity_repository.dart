import 'package:hati/features/activity/data/activity_repository.dart';
import 'package:hati/features/activity/domain/activity_event.dart';
import 'package:hati/features/activity/domain/comment.dart';

/// An in-memory [ActivityRepository] for tests.
///
/// Paging is modelled the way the RPC does it — strictly older than `before` —
/// so a test can tell a working pager from one that repeats itself.
class FakeActivityRepository implements ActivityRepository {
  FakeActivityRepository({List<ActivityEvent>? events, List<Comment>? comments})
    : events = events ?? <ActivityEvent>[],
      commentList = comments ?? <Comment>[];

  final List<ActivityEvent> events;
  final List<Comment> commentList;

  ActivityFailure? failWith;
  final List<String> calls = <String>[];
  Map<String, Object?> lastArgs = <String, Object?>{};

  @override
  Future<List<ActivityEvent>> feed({
    String? groupId,
    int limit = 30,
    DateTime? before,
  }) async {
    calls.add('feed');
    lastArgs = {'groupId': groupId, 'limit': limit, 'before': before};
    _maybeFail();

    final sorted = [...events]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return sorted
        .where((e) => groupId == null || e.groupId == groupId)
        .where((e) => before == null || e.createdAt.isBefore(before))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<Comment>> comments(String billId) async {
    calls.add('comments');
    _maybeFail();
    return commentList.where((c) => c.billId == billId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> addComment({
    required String billId,
    required String body,
  }) async {
    calls.add('addComment');
    lastArgs = {'billId': billId, 'body': body};
    _maybeFail();
    commentList.add(
      Comment(
        id: 'c${commentList.length + 1}',
        billId: billId,
        authorId: 'carlo',
        authorName: 'Carlo',
        body: body,
        createdAt: DateTime.utc(2026, 9, 22),
      ),
    );
  }

  @override
  Future<void> editComment({
    required String commentId,
    required String body,
  }) async {
    calls.add('editComment');
    lastArgs = {'commentId': commentId, 'body': body};
    _maybeFail();
  }

  @override
  Future<void> deleteComment(String commentId) async {
    calls.add('deleteComment');
    lastArgs = {'commentId': commentId};
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
