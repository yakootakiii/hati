import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../notifications/presentation/notifications_controller.dart';
import '../data/groups_repository.dart';
import '../domain/group_failure.dart';
import '../domain/group_models.dart';

part 'groups_controller.g.dart';

@riverpod
Future<List<GroupSummary>> myGroups(Ref ref) =>
    ref.watch(groupsRepositoryProvider).myGroups();

@riverpod
Future<List<GroupMember>> groupMembers(Ref ref, String groupId) =>
    ref.watch(groupsRepositoryProvider).members(groupId);

@riverpod
Future<InviteLink?> activeInvite(Ref ref, String groupId) =>
    ref.watch(groupsRepositoryProvider).activeInvite(groupId);

/// The bills blocking someone from leaving, so the confirmation dialog can
/// name them (spec §12.3).
@riverpod
Future<List<LeaveBlocker>> leaveBlockers(
  Ref ref,
  String groupId, {
  String? userId,
}) =>
    ref.watch(groupsRepositoryProvider).leaveBlockers(groupId, userId: userId);

/// Search results for the invite sheet. The sheet debounces, so this only
/// runs once typing settles; under two characters it is empty rather than an
/// error, since that is simply "not searching yet".
@riverpod
Future<List<PersonResult>> peopleSearch(
  Ref ref,
  String groupId,
  String query,
) async {
  final trimmed = query.trim();
  if (trimmed.length < 2) return const <PersonResult>[];
  return ref.watch(groupsRepositoryProvider).searchPeople(groupId, trimmed);
}

/// Invites waiting on the signed-in user (DECISIONS D-57).
@riverpod
Future<List<DirectInvite>> myDirectInvites(Ref ref) =>
    ref.watch(groupsRepositoryProvider).myDirectInvites();

/// Every group mutation, with the resulting cache invalidation in one place so
/// no screen has to remember what to refresh.
@Riverpod(keepAlive: true)
class GroupActions extends _$GroupActions {
  @override
  FutureOr<void> build() {}

  /// The message for the most recent failure.
  ///
  /// Read this instead of `ref` after an await: these actions invalidate the
  /// providers that built the calling widget, so the widget — and its ref —
  /// may be disposed by the time the future completes.
  String? lastError;

  /// Returns the new group's id, or null if it failed.
  Future<String?> createGroup({required String name, String? photoPath}) async {
    return _run(() async {
      final id = await ref
          .read(groupsRepositoryProvider)
          .createGroup(name: name, photoPath: photoPath);
      ref.invalidate(myGroupsProvider);
      return id;
    });
  }

  Future<bool> rename({required String groupId, required String name}) =>
      updateGroup(groupId: groupId, name: name);

  /// Renames the group, sets its photo, or both.
  Future<bool> updateGroup({
    required String groupId,
    String? name,
    String? photoPath,
  }) async {
    final result = await _run(() async {
      await ref
          .read(groupsRepositoryProvider)
          .updateGroup(groupId: groupId, name: name, photoPath: photoPath);
      ref.invalidate(myGroupsProvider);
      return true;
    });
    return result ?? false;
  }

  Future<bool> setArchived({
    required String groupId,
    required bool archived,
  }) async {
    final result = await _run(() async {
      await ref
          .read(groupsRepositoryProvider)
          .updateGroup(groupId: groupId, archived: archived);
      ref.invalidate(myGroupsProvider);
      return true;
    });
    return result ?? false;
  }

  /// Mints a link, replacing the existing one when [reset] is set (spec §8).
  Future<InviteLink?> createInvite(
    String groupId, {
    int? expiresInHours,
    int? maxUses,
    bool reset = false,
  }) async {
    return _run(() async {
      final link = await ref
          .read(groupsRepositoryProvider)
          .createInvite(
            groupId,
            expiresInHours: expiresInHours,
            maxUses: maxUses,
            resetExisting: reset,
          );
      ref.invalidate(activeInviteProvider(groupId));
      return link;
    });
  }

  Future<bool> leave(String groupId) async {
    final result = await _run(() async {
      await ref.read(groupsRepositoryProvider).leaveGroup(groupId);
      ref.invalidate(myGroupsProvider);
      return true;
    });
    return result ?? false;
  }

  Future<bool> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final result = await _run(() async {
      await ref
          .read(groupsRepositoryProvider)
          .removeMember(groupId: groupId, userId: userId);
      ref
        ..invalidate(groupMembersProvider(groupId))
        ..invalidate(myGroupsProvider);
      return true;
    });
    return result ?? false;
  }

  Future<bool> setRole({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    final result = await _run(() async {
      await ref
          .read(groupsRepositoryProvider)
          .setMemberRole(groupId: groupId, userId: userId, role: role);
      ref
        ..invalidate(groupMembersProvider(groupId))
        ..invalidate(myGroupsProvider);
      return true;
    });
    return result ?? false;
  }

  /// Invites someone found by [peopleSearch]. Returns true on success.
  Future<bool> invitePerson({
    required String groupId,
    required String userId,
  }) async {
    final result = await _run(() async {
      await ref
          .read(groupsRepositoryProvider)
          .invitePerson(groupId: groupId, userId: userId);
      ref.invalidate(peopleSearchProvider);
      return true;
    });
    return result ?? false;
  }

  Future<bool> cancelDirectInvite(String inviteId) async {
    final result = await _run(() async {
      await ref.read(groupsRepositoryProvider).cancelDirectInvite(inviteId);
      ref.invalidate(peopleSearchProvider);
      return true;
    });
    return result ?? false;
  }

  /// Joins or declines. Returns the group id, or null if it failed — an
  /// invite answered elsewhere, or cancelled meanwhile, lands in [lastError].
  Future<String?> respondToInvite(
    String inviteId, {
    required bool accept,
  }) async {
    final groupId = await _run(
      () => ref
          .read(groupsRepositoryProvider)
          .respondToInvite(inviteId, accept: accept),
    );
    // Refreshed on failure too: a stale invite should drop out of view.
    ref
      ..invalidate(myDirectInvitesProvider)
      ..invalidate(myGroupsProvider)
      ..invalidate(notificationListProvider)
      ..invalidate(unreadNotificationCountProvider);
    return groupId;
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      lastError = null;
      state = const AsyncValue<void>.data(null);
      return value;
    } on GroupFailure catch (failure, stackTrace) {
      lastError = failure.displayMessage;
      state = AsyncValue<void>.error(failure, stackTrace);
      return null;
    }
  }
}

/// The message to show for a controller error, or null when there is none.
String? groupErrorMessage(AsyncValue<void> state) {
  final error = state.error;
  if (error == null) return null;
  if (error is GroupFailure) return error.displayMessage;
  return 'Something went wrong. Try again.';
}
