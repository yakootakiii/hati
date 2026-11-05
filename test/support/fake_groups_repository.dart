import 'package:hati/features/groups/data/groups_repository.dart';
import 'package:hati/features/groups/domain/group_failure.dart';
import 'package:hati/features/groups/domain/group_models.dart';

/// An in-memory [GroupsRepository] for tests.
///
/// Models just enough of the server's behaviour to exercise the controllers:
/// calls are recorded, and [failWith] makes the next call throw.
class FakeGroupsRepository implements GroupsRepository {
  FakeGroupsRepository({
    List<GroupSummary>? groups,
    List<GroupMember>? members,
    List<LeaveBlocker>? blockers,
    InvitePreview? preview,
    List<PersonResult>? people,
    List<DirectInvite>? directInvites,
  }) : people = people ?? <PersonResult>[],
       directInvites = directInvites ?? <DirectInvite>[],
       groups = groups ?? <GroupSummary>[],
       memberList = members ?? <GroupMember>[],
       blockerList = blockers ?? <LeaveBlocker>[],
       preview =
           preview ??
           const InvitePreview.valid(
             groupId: 'g1',
             groupName: 'Tagaytay Staycation',
             memberCount: 3,
             alreadyMember: false,
             inviterName: 'Bea',
           );

  final List<GroupSummary> groups;
  final List<GroupMember> memberList;
  final List<LeaveBlocker> blockerList;
  InvitePreview preview;
  final List<PersonResult> people;
  final List<DirectInvite> directInvites;

  GroupFailure? failWith;
  final List<String> calls = <String>[];
  Map<String, Object?> lastArgs = <String, Object?>{};

  /// Arguments per call, for when a later refresh overwrites [lastArgs].
  final Map<String, Map<String, Object?>> argsByCall =
      <String, Map<String, Object?>>{};

  int myGroupsCalls = 0;

  @override
  Future<List<GroupSummary>> myGroups() async {
    myGroupsCalls++;
    _maybeFail();
    return groups;
  }

  @override
  Future<String> createGroup({required String name, String? photoPath}) async {
    calls.add('createGroup');
    lastArgs = {'name': name, 'photoPath': photoPath};
    _maybeFail();
    return 'new-group-id';
  }

  @override
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? photoPath,
    bool? archived,
  }) async {
    calls.add('updateGroup');
    lastArgs = {
      'groupId': groupId,
      'name': name,
      'photoPath': photoPath,
      'archived': archived,
    };
    _maybeFail();
  }

  @override
  Future<List<GroupMember>> members(String groupId) async {
    calls.add('members');
    _maybeFail();
    return memberList;
  }

  @override
  Future<InviteLink?> activeInvite(String groupId) async {
    calls.add('activeInvite');
    _maybeFail();
    return const InviteLink(id: 'i1', token: 'existing-token-1234567890');
  }

  @override
  Future<InviteLink> createInvite(
    String groupId, {
    int? expiresInHours,
    int? maxUses,
    bool resetExisting = false,
  }) async {
    calls.add('createInvite');
    lastArgs = {
      'groupId': groupId,
      'expiresInHours': expiresInHours,
      'maxUses': maxUses,
      'resetExisting': resetExisting,
    };
    _maybeFail();
    return const InviteLink(id: 'i2', token: 'fresh-token-0987654321');
  }

  @override
  Future<InvitePreview> previewInvite(String token) async {
    calls.add('previewInvite');
    lastArgs = {'token': token};
    _maybeFail();
    return preview;
  }

  @override
  Future<String> joinGroup(String token) async {
    calls.add('joinGroup');
    lastArgs = {'token': token};
    _maybeFail();
    return 'g1';
  }

  @override
  Future<List<LeaveBlocker>> leaveBlockers(
    String groupId, {
    String? userId,
  }) async {
    calls.add('leaveBlockers');
    _maybeFail();
    return blockerList;
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    calls.add('leaveGroup');
    lastArgs = {'groupId': groupId};
    _maybeFail();
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    calls.add('removeMember');
    lastArgs = {'groupId': groupId, 'userId': userId};
    _maybeFail();
  }

  @override
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    calls.add('setMemberRole');
    lastArgs = {'groupId': groupId, 'userId': userId, 'role': role};
    _maybeFail();
  }

  @override
  Future<List<PersonResult>> searchPeople(String groupId, String query) async {
    calls.add('searchPeople');
    lastArgs = {'groupId': groupId, 'query': query};
    _maybeFail();
    return people;
  }

  @override
  Future<String> invitePerson({
    required String groupId,
    required String userId,
  }) async {
    calls.add('invitePerson');
    lastArgs = argsByCall['invitePerson'] = {
      'groupId': groupId,
      'userId': userId,
    };
    _maybeFail();
    return 'direct-invite-1';
  }

  @override
  Future<String> respondToInvite(
    String inviteId, {
    required bool accept,
  }) async {
    calls.add('respondToInvite');
    lastArgs = {'inviteId': inviteId, 'accept': accept};
    _maybeFail();
    directInvites.removeWhere((invite) => invite.id == inviteId);
    return 'g1';
  }

  @override
  Future<void> cancelDirectInvite(String inviteId) async {
    calls.add('cancelDirectInvite');
    lastArgs = argsByCall['cancelDirectInvite'] = {'inviteId': inviteId};
    _maybeFail();
  }

  @override
  Future<List<DirectInvite>> myDirectInvites() async {
    calls.add('myDirectInvites');
    _maybeFail();
    return directInvites;
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }
}
