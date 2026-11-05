import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/avatar_stack.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';
import '../widgets/direct_invite_widgets.dart';

class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    // A failure here only hides the invites; the groups still load.
    final invites =
        ref.watch(myDirectInvitesProvider).asData?.value ??
        const <DirectInvite>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.createGroup),
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(
          message: error is Exception
              ? 'Could not load your groups.'
              : 'Something went wrong.',
          onRetry: () => ref.invalidate(myGroupsProvider),
        ),
        data: (all) {
          // Someone invited by name before they have any group must still see
          // the invite, so an invite suppresses the empty state.
          if (all.isEmpty && invites.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'No groups yet',
              message:
                  'Make one for your next trip, dinner or shared bill — then '
                  'invite your barkada.',
              actionLabel: 'New group',
              actionIcon: Icons.add,
              onAction: () => context.push(Routes.createGroup),
            );
          }

          final active = all.where((g) => !g.isArchived).toList();
          final archived = all.where((g) => g.isArchived).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myDirectInvitesProvider)
                ..invalidate(myGroupsProvider);
              await ref.read(myGroupsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (invites.isNotEmpty) ...[
                        const SectionHeader('Invitations'),
                        for (final invite in invites) ...[
                          DirectInviteCard(invite: invite),
                          const SizedBox(height: kSpace),
                        ],
                      ],
                      if (active.isNotEmpty) ...[
                        SectionHeader(
                          active.length == 1
                              ? '1 group'
                              : '${active.length} groups',
                        ),
                        ListGroup(
                          dividerIndent: 72,
                          children: [
                            for (final group in active) _GroupRow(group: group),
                          ],
                        ),
                      ],
                      if (archived.isNotEmpty) ...[
                        const SizedBox(height: kSpace * 2),
                        ExpansionTile(
                          title: Text(
                            'Archived (${archived.length})',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          childrenPadding:
                              const EdgeInsets.only(bottom: kSpace),
                          children: [
                            ListGroup(
                              dividerIndent: 72,
                              children: [
                                for (final group in archived)
                                  _GroupRow(group: group),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberWord = group.memberCount == 1 ? 'member' : 'members';
    final initial =
        group.name.trim().isEmpty ? '?' : group.name.trim()[0].toUpperCase();

    return InkWell(
      onTap: () => context.push(Routes.groupDetail(group.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            // A monogram tile: groups are places, not people, so they get a
            // square rather than an avatar circle.
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.memberCount} $memberWord',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: kSpace),
            AvatarStack(
              radius: 13,
              people: [
                for (final m in group.members)
                  StackedAvatar(
                    displayName: m.displayName,
                    avatarPath: m.avatarPath,
                  ),
              ],
              total: group.memberCount,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
