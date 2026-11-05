import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/group_failure.dart';
import '../domain/group_models.dart';

part 'groups_repository.g.dart';

/// Everything the app does with groups, invites and membership.
///
/// Membership tables are not client-writable, so every mutation here is an RPC
/// call; only reads go through PostgREST directly, gated by RLS.
abstract interface class GroupsRepository {
  Future<List<GroupSummary>> myGroups();

  Future<String> createGroup({required String name, String? photoPath});

  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? photoPath,
    bool? archived,
  });

  Future<List<GroupMember>> members(String groupId);

  /// The group's current usable link, or null if there is none.
  Future<InviteLink?> activeInvite(String groupId);

  Future<InviteLink> createInvite(
    String groupId, {
    int? expiresInHours,
    int? maxUses,
    bool resetExisting = false,
  });

  Future<InvitePreview> previewInvite(String token);

  /// Returns the group id joined. Idempotent for an existing member.
  Future<String> joinGroup(String token);

  Future<List<LeaveBlocker>> leaveBlockers(String groupId, {String? userId});

  Future<void> leaveGroup(String groupId);

  Future<void> removeMember({required String groupId, required String userId});

  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required String role,
  });

  /// People an owner or admin could invite, by name or exact email (D-57).
  Future<List<PersonResult>> searchPeople(String groupId, String query);

  /// Returns the invite id. Idempotent while the invite is pending.
  Future<String> invitePerson({
    required String groupId,
    required String userId,
  });

  /// Returns the invite's group id.
  Future<String> respondToInvite(String inviteId, {required bool accept});

  Future<void> cancelDirectInvite(String inviteId);

  Future<List<DirectInvite>> myDirectInvites();
}

class SupabaseGroupsRepository implements GroupsRepository {
  SupabaseGroupsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GroupSummary>> myGroups() {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>('get_my_groups');
      return rows
          .cast<Map<String, dynamic>>()
          .map(GroupSummary.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<String> createGroup({required String name, String? photoPath}) {
    return _guard(() async {
      return await _client.rpc<String>(
        'create_group',
        params: {'p_name': name, 'p_photo_path': photoPath},
      );
    });
  }

  @override
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? photoPath,
    bool? archived,
  }) {
    return _guard(() async {
      final patch = <String, dynamic>{
        if (name != null) 'name': name,
        if (photoPath != null) 'photo_path': photoPath,
        if (archived != null)
          'archived_at': archived
              ? DateTime.now().toUtc().toIso8601String()
              : null,
      };
      if (patch.isEmpty) return;
      await _client.from('groups').update(patch).eq('id', groupId);
    });
  }

  @override
  Future<List<GroupMember>> members(String groupId) {
    return _guard(() async {
      final rows = await _client
          .from('group_members')
          .select(
            'user_id, role, joined_at, profiles(display_name, avatar_path)',
          )
          .eq('group_id', groupId)
          .isFilter('left_at', null);

      return rows
          .map((row) {
            final profile = row['profiles'] as Map<String, dynamic>?;
            return GroupMember(
              userId: row['user_id'] as String,
              role: row['role'] as String,
              displayName: profile?['display_name'] as String? ?? 'Someone',
              avatarPath: profile?['avatar_path'] as String?,
              joinedAt: DateTime.tryParse(row['joined_at'] as String? ?? ''),
            );
          })
          .toList(growable: false);
    });
  }

  @override
  Future<InviteLink?> activeInvite(String groupId) {
    return _guard(() async {
      final rows = await _client
          .from('group_invites')
          .select('id, token, expires_at, max_uses, use_count')
          .eq('group_id', groupId)
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) return null;
      final link = InviteLink.fromJson(rows.first);
      // A link past its expiry or use limit is no longer offerable, even
      // though the row is still there.
      return link.isExpired || link.isExhausted ? null : link;
    });
  }

  @override
  Future<InviteLink> createInvite(
    String groupId, {
    int? expiresInHours,
    int? maxUses,
    bool resetExisting = false,
  }) {
    return _guard(() async {
      final result = await _client.rpc<Map<String, dynamic>>(
        'create_invite',
        params: {
          'p_group_id': groupId,
          'p_expires_in_hours': expiresInHours,
          'p_max_uses': maxUses,
          'p_revoke_existing': resetExisting,
        },
      );
      return InviteLink.fromJson(result);
    });
  }

  @override
  Future<InvitePreview> previewInvite(String token) {
    return _guard(() async {
      final result = await _client.rpc<Map<String, dynamic>>(
        'get_invite_preview',
        params: {'p_token': token},
      );
      return InvitePreview.fromJson(result);
    });
  }

  @override
  Future<String> joinGroup(String token) {
    return _guard(
      () => _client.rpc<String>('join_group', params: {'p_token': token}),
    );
  }

  @override
  Future<List<LeaveBlocker>> leaveBlockers(String groupId, {String? userId}) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'group_leave_blockers',
        params: {
          'p_group_id': groupId,
          if (userId != null) 'p_user_id': userId,
        },
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(LeaveBlocker.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<void> leaveGroup(String groupId) {
    return _guard(
      () => _client.rpc<void>('leave_group', params: {'p_group_id': groupId}),
    );
  }

  @override
  Future<void> removeMember({required String groupId, required String userId}) {
    return _guard(
      () => _client.rpc<void>(
        'remove_member',
        params: {'p_group_id': groupId, 'p_user_id': userId},
      ),
    );
  }

  @override
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required String role,
  }) {
    return _guard(
      () => _client.rpc<void>(
        'set_member_role',
        params: {'p_group_id': groupId, 'p_user_id': userId, 'p_role': role},
      ),
    );
  }

  @override
  Future<List<PersonResult>> searchPeople(String groupId, String query) {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'search_people',
        params: {'p_group_id': groupId, 'p_query': query},
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(PersonResult.fromJson)
          .toList(growable: false);
    });
  }

  @override
  Future<String> invitePerson({
    required String groupId,
    required String userId,
  }) {
    return _guard(
      () => _client.rpc<String>(
        'invite_person',
        params: {'p_group_id': groupId, 'p_user_id': userId},
      ),
    );
  }

  @override
  Future<String> respondToInvite(String inviteId, {required bool accept}) {
    return _guard(
      () => _client.rpc<String>(
        'respond_to_invite',
        params: {'p_invite_id': inviteId, 'p_accept': accept},
      ),
    );
  }

  @override
  Future<void> cancelDirectInvite(String inviteId) {
    return _guard(
      () => _client.rpc<void>(
        'cancel_direct_invite',
        params: {'p_invite_id': inviteId},
      ),
    );
  }

  @override
  Future<List<DirectInvite>> myDirectInvites() {
    return _guard(() async {
      final rows = await _client.rpc<List<dynamic>>('get_my_direct_invites');
      return rows
          .cast<Map<String, dynamic>>()
          .map(DirectInvite.fromJson)
          .toList(growable: false);
    });
  }

  /// Turns Postgres errors into [GroupFailure] so no screen reads a raw
  /// PostgrestException.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw GroupFailure.fromCode(error.code, error.message);
    } on SocketException catch (_) {
      throw const GroupFailure(
        GroupFailureKind.network,
        "Can't reach Hati right now.",
      );
    }
  }
}

@Riverpod(keepAlive: true)
GroupsRepository groupsRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    throw StateError(
      'Groups need a Supabase project; see ConfigMissingScreen.',
    );
  }
  return SupabaseGroupsRepository(Supabase.instance.client);
}
