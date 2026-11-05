import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/groups/data/groups_repository.dart';
import 'package:hati/features/groups/domain/group_failure.dart';
import 'package:hati/features/groups/domain/group_models.dart';
import 'package:hati/features/groups/presentation/groups_controller.dart';
import 'package:hati/features/groups/presentation/join_controller.dart';

import '../../support/fake_groups_repository.dart';

void main() {
  late FakeGroupsRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeGroupsRepository();
    container = ProviderContainer(
      overrides: [groupsRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  GroupActions actions() => container.read(groupActionsProvider.notifier);
  JoinController join() => container.read(joinControllerProvider.notifier);

  test('createGroup returns the new id and refreshes the list', () async {
    await container.read(myGroupsProvider.future);
    expect(repository.myGroupsCalls, 1);

    final id = await actions().createGroup(name: 'Tagaytay Staycation');

    expect(id, 'new-group-id');
    expect(repository.lastArgs['name'], 'Tagaytay Staycation');

    await container.read(myGroupsProvider.future);
    expect(repository.myGroupsCalls, 2, reason: 'the list was invalidated');
  });

  test('a failed action surfaces the failure and returns null', () async {
    repository.failWith = const GroupFailure(
      GroupFailureKind.invalidInput,
      'Give the group a name',
    );

    final id = await actions().createGroup(name: '  ');

    expect(id, isNull);
    final state = container.read(groupActionsProvider);
    expect(state.hasError, isTrue);
    expect(groupErrorMessage(state), 'Give the group a name');
  });

  test('reset passes revoke_existing so the old link dies (spec §8)', () async {
    await actions().createInvite('g1', reset: true);

    expect(repository.calls, contains('createInvite'));
    expect(repository.lastArgs['resetExisting'], isTrue);
  });

  test('a first invite does not revoke anything', () async {
    await actions().createInvite('g1');
    expect(repository.lastArgs['resetExisting'], isFalse);
  });

  test('leaving while blocked reports the bills the server named', () async {
    repository.failWith = const GroupFailure(
      GroupFailureKind.outstandingBalance,
      'Settle up first: Airbnb – 2 nights',
    );

    expect(await actions().leave('g1'), isFalse);
    expect(
      groupErrorMessage(container.read(groupActionsProvider)),
      contains('Airbnb'),
    );
  });

  test('an owner is told to hand over first', () async {
    repository.failWith = const GroupFailure(
      GroupFailureKind.ownerMustTransfer,
      'Make someone else the owner before you leave',
    );

    expect(await actions().leave('g1'), isFalse);
    expect(
      groupErrorMessage(container.read(groupActionsProvider)),
      contains('owner'),
    );
  });

  test('setRole forwards the role and refreshes the member list', () async {
    await container.read(groupMembersProvider('g1').future);
    final before = repository.calls.where((c) => c == 'members').length;

    expect(
      await actions().setRole(groupId: 'g1', userId: 'u2', role: 'owner'),
      isTrue,
    );
    expect(repository.lastArgs['role'], 'owner');

    await container.read(groupMembersProvider('g1').future);
    expect(
      repository.calls.where((c) => c == 'members').length,
      before + 1,
      reason: 'the member list was invalidated',
    );
  });

  test('removeMember forwards both ids', () async {
    expect(
      await actions().removeMember(groupId: 'g1', userId: 'u2'),
      isTrue,
    );
    expect(repository.lastArgs['groupId'], 'g1');
    expect(repository.lastArgs['userId'], 'u2');
  });

  test('archiving sends the flag rather than deleting anything', () async {
    expect(
      await actions().setArchived(groupId: 'g1', archived: true),
      isTrue,
    );
    expect(repository.calls, contains('updateGroup'));
    expect(repository.lastArgs['archived'], isTrue);
  });

  group('join', () {
    test('returns the joined group and refreshes the list', () async {
      await container.read(myGroupsProvider.future);
      final before = repository.myGroupsCalls;

      expect(await join().join('tok'), 'g1');
      expect(repository.lastArgs['token'], 'tok');

      await container.read(myGroupsProvider.future);
      expect(repository.myGroupsCalls, before + 1);
    });

    test('a revoked link fails with copy pointing at a new link', () async {
      repository.failWith = const GroupFailure(
        GroupFailureKind.inviteRevoked,
        'That invite link was reset',
      );

      expect(await join().join('tok'), isNull);
      expect(
        groupErrorMessage(container.read(joinControllerProvider)),
        contains('Ask for a new one'),
      );
    });

    test('previewing a token asks the server about that exact token', () async {
      final preview = await container.read(invitePreviewProvider('abc').future);

      expect(repository.lastArgs['token'], 'abc');
      expect(preview, isA<ValidInvitePreview>());
    });
  });
}
