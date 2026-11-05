import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/groups_repository.dart';
import '../domain/group_failure.dart';
import '../domain/group_models.dart';
import 'groups_controller.dart';

part 'join_controller.g.dart';

@riverpod
Future<InvitePreview> invitePreview(Ref ref, String token) =>
    ref.watch(groupsRepositoryProvider).previewInvite(token);

@riverpod
class JoinController extends _$JoinController {
  @override
  FutureOr<void> build() {}

  /// Returns the joined group's id, or null on failure.
  Future<String?> join(String token) async {
    state = const AsyncValue<void>.loading();
    try {
      final groupId = await ref.read(groupsRepositoryProvider).joinGroup(token);
      ref.invalidate(myGroupsProvider);
      state = const AsyncValue<void>.data(null);
      return groupId;
    } on GroupFailure catch (failure, stackTrace) {
      state = AsyncValue<void>.error(failure, stackTrace);
      return null;
    }
  }
}
