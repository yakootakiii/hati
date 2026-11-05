import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/avatar_stack.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../activity/presentation/activity_controller.dart';
import '../../../activity/presentation/widgets/activity_feed.dart';
import '../../../bills/presentation/widgets/balances_tab.dart';
import '../../../bills/presentation/widgets/bills_tab.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';
import '../widgets/invite_sheet.dart';

/// Group detail (spec §10). The Bills and Balances tabs fill in at M4 and the
/// Activity feed at M7; the structure is here so those land as content, not
/// navigation changes.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return groups.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(
          message: 'Could not load this group.',
          onRetry: () => ref.invalidate(myGroupsProvider),
        ),
      ),
      data: (all) {
        final group = all.where((g) => g.id == groupId).firstOrNull;
        if (group == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off,
              title: 'Group not found',
              message: "You're not a member of this group any more.",
            ),
          );
        }
        return _Loaded(group: group);
      },
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Live while this screen is open (spec §4.3).
    ref.watch(groupRealtimeProvider(group.id));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: group.isArchived
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.push(Routes.addBill(group.id)),
                icon: const Icon(Icons.add),
                label: const Text('Add bill'),
              ),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(group.name, overflow: TextOverflow.ellipsis),
              Text(
                '${group.memberCount} '
                '${group.memberCount == 1 ? 'member' : 'members'} · '
                "You're ${group.role == 'member' ? 'a' : 'the'} ${group.role}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            // The faces double as the way into Members.
            Semantics(
              button: true,
              label: 'Members',
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadiusMd),
                onTap: () => context.push(Routes.groupMembers(group.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: ExcludeSemantics(
                    child: AvatarStack(
                      radius: 12,
                      people: [
                        for (final m in group.members)
                          StackedAvatar(
                            displayName: m.displayName,
                            avatarPath: m.avatarPath,
                          ),
                      ],
                      total: group.memberCount,
                    ),
                  ),
                ),
              ),
            ),
            if (group.canInvite)
              IconButton(
                onPressed: () => InviteSheet.show(
                  context,
                  groupId: group.id,
                  groupName: group.name,
                ),
                icon: const Icon(Icons.person_add_alt),
                tooltip: 'Invite people',
              ),
            PopupMenuButton<String>(
              onSelected: (value) => switch (value) {
                'members' => context.push(Routes.groupMembers(group.id)),
                'recurring' => context.push(Routes.recurring(group.id)),
                'settings' => context.push(Routes.groupSettings(group.id)),
                'invite' => InviteSheet.show(
                  context,
                  groupId: group.id,
                  groupName: group.name,
                ),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'members', child: Text('Members')),
                const PopupMenuItem(
                  value: 'recurring',
                  child: Text('Repeating bills'),
                ),
                if (group.canInvite)
                  const PopupMenuItem(
                    value: 'invite',
                    child: Text('Invite people'),
                  ),
                if (group.canInvite)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Group settings'),
                  ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Bills'),
              Tab(text: 'Balances'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  BillsTab(groupId: group.id),
                  BalancesTab(groupId: group.id),
                  ActivityFeed(groupId: group.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
