import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/auth/domain/auth_snapshot.dart';
import 'package:hati/features/groups/domain/group_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_groups_repository.dart';

void main() {
  testWidgets('the Groups tab offers one clear action when empty (spec §10.1)',
      (tester) async {
    final harness = await pumpApp(tester, session: signedIn);
    await harness.go('/groups');

    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New group'), findsOneWidget);
  });

  testWidgets('a group card shows its name and member count', (tester) async {
    final harness = await pumpApp(
      tester,
      session: signedIn,
      groups: FakeGroupsRepository(
        groups: const [
          GroupSummary(
            id: 'g1',
            name: 'Tagaytay Staycation',
            role: 'owner',
            memberCount: 4,
            members: [
              GroupMemberProfile(id: 'u1', displayName: 'Bea'),
              GroupMemberProfile(id: 'u2', displayName: 'Carlo'),
            ],
          ),
        ],
      ),
    );
    await harness.go('/groups');

    expect(find.text('Tagaytay Staycation'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
  });

  testWidgets('archived groups are tucked into their own section',
      (tester) async {
    final harness = await pumpApp(
      tester,
      session: signedIn,
      groups: FakeGroupsRepository(
        groups: [
          const GroupSummary(
            id: 'g1',
            name: 'Active Trip',
            role: 'owner',
            memberCount: 2,
          ),
          GroupSummary(
            id: 'g2',
            name: 'Old Trip',
            role: 'member',
            memberCount: 3,
            archivedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await harness.go('/groups');

    expect(find.text('Active Trip'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
  });

  group('join screen (spec §8)', () {
    testWidgets('a valid link shows the group and who invited you',
        (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/join/good-token');

      expect(find.text('Tagaytay Staycation'), findsOneWidget);
      expect(find.textContaining('Bea invited you'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join group'), findsOneWidget);
    });

    testWidgets('an existing member is offered Open, not Join', (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedIn,
        groups: FakeGroupsRepository(
          preview: const InvitePreview.valid(
            groupId: 'g1',
            groupName: 'Tagaytay Staycation',
            memberCount: 3,
            alreadyMember: true,
          ),
        ),
      );
      await harness.go('/join/good-token');

      expect(find.widgetWithText(FilledButton, 'Open group'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join group'), findsNothing);
    });

    testWidgets('a revoked link says so without naming the group',
        (tester) async {
      final harness = await pumpApp(
        tester,
        session: signedIn,
        groups: FakeGroupsRepository(
          preview: const InvitePreview.invalid(InviteInvalidReason.revoked),
        ),
      );
      await harness.go('/join/dead-token');

      expect(find.textContaining('was reset'), findsOneWidget);
      expect(find.textContaining('Ask for a new one'), findsOneWidget);
      expect(find.text('Tagaytay Staycation'), findsNothing);
    });

    for (final (reason, needle) in const [
      (InviteInvalidReason.expired, 'has expired'),
      (InviteInvalidReason.exhausted, 'been used up'),
      (InviteInvalidReason.notFound, "isn't valid"),
    ]) {
      testWidgets('${reason.name} gets its own copy', (tester) async {
        final harness = await pumpApp(
          tester,
          session: signedIn,
          groups: FakeGroupsRepository(
            preview: InvitePreview.invalid(reason),
          ),
        );
        await harness.go('/join/bad-token');

        expect(find.textContaining(needle), findsOneWidget);
      });
    }

    testWidgets('joining navigates into the group', (tester) async {
      final harness = await pumpApp(tester, session: signedIn);
      await harness.go('/join/good-token');

      await tester.tap(find.widgetWithText(FilledButton, 'Join group'));
      await tester.pumpAndSettle();

      expect(harness.groups.calls, contains('joinGroup'));
      expect(harness.location, '/groups/g1');
    });
  });

  group('invite deep link through auth (spec §8.1)', () {
    testWidgets('a signed-out tap is parked at Welcome, then resumed',
        (tester) async {
      final harness = await pumpApp(tester);

      await harness.go('/join/stashed-token');
      expect(
        harness.location,
        '/welcome',
        reason: 'signed out, the link cannot be opened yet',
      );
      expect(find.text('Sign up with email'), findsOneWidget);

      harness.auth.signInAs('carlo');
      await tester.pumpAndSettle();

      expect(
        harness.location,
        '/join/stashed-token',
        reason: 'the stashed token resumes once there is a session',
      );
      expect(find.widgetWithText(FilledButton, 'Join group'), findsOneWidget);
    });

    testWidgets('signing in with no invite pending goes Home', (tester) async {
      final harness = await pumpApp(tester);
      expect(harness.location, '/welcome');

      harness.auth.signInAs('carlo');
      await tester.pumpAndSettle();

      expect(harness.location, '/');
    });

    testWidgets('a stashed token is consumed, not replayed', (tester) async {
      final harness = await pumpApp(tester);
      await harness.go('/join/one-shot');

      harness.auth.signInAs('carlo');
      await tester.pumpAndSettle();
      expect(harness.location, '/join/one-shot');

      // Move off the invite before signing out. Signing out while still on
      // /join/... would stash the token again, which is the right behaviour —
      // this test is about the stash being one-shot.
      await harness.go('/');
      harness.auth.emit(const AuthSnapshot.signedOut());
      await tester.pumpAndSettle();
      harness.auth.signInAs('carlo');
      await tester.pumpAndSettle();

      expect(
        harness.location,
        '/',
        reason: 'the token was consumed by the first resume',
      );
    });
  });
}
