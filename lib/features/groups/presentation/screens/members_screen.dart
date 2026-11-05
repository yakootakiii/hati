import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';

/// Members (spec §10): roles, promote/demote/remove for owners and admins,
/// and Leave group for yourself.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(groupId));
    final myId = ref.watch(sessionStateProvider).userId;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load the members.',
          onRetry: () => ref.invalidate(groupMembersProvider(groupId)),
        ),
        data: (list) {
          final me = list.where((m) => m.userId == myId).firstOrNull;
          final iAmOwner = me?.isOwner ?? false;
          final iCanManage = iAmOwner || (me?.isAdmin ?? false);

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: kSpace),
            children: [
              for (final member in list)
                _MemberTile(
                  groupId: groupId,
                  member: member,
                  isMe: member.userId == myId,
                  iAmOwner: iAmOwner,
                  iCanManage: iCanManage,
                ),
              const Divider(height: kSpace * 4),
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Leave group',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => _confirmLeave(context, ref),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(groupActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final blockers = await showDialog<_LeaveChoice>(
      context: context,
      builder: (_) => _LeaveDialog(groupId: groupId),
    );

    if (blockers != _LeaveChoice.confirm) return;

    final ok = await actions.leave(groupId);

    if (ok) {
      router.go('/groups');
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(actions.lastError ?? 'Could not leave the group.'),
        ),
      );
    }
  }
}

enum _LeaveChoice { cancel, confirm }

/// Loads the blocking bills before asking, so the dialog can name them rather
/// than waiting for the server to refuse (spec §12.3).
class _LeaveDialog extends ConsumerWidget {
  const _LeaveDialog({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockers = ref.watch(leaveBlockersProvider(groupId));

    return AlertDialog(
      title: const Text('Leave this group?'),
      content: blockers.when(
        loading: () => const SizedBox(
          height: 64,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) =>
            const Text('Could not check your balances. Try again.'),
        data: (list) => list.isEmpty
            ? const Text(
                "You're all square. You'll lose access to this group's bills, "
                'but your history stays.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Settle these first:'),
                  const SizedBox(height: kSpace),
                  for (final blocker in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: kSpace / 2),
                      child: Text(
                        '• ${blocker.title} — '
                        '${blocker.isOwedToThem ? 'owed to you' : 'you owe'} '
                        '${Money(blocker.amount).format()}',
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LeaveChoice.cancel),
          child: const Text('Cancel'),
        ),
        if (blockers.asData?.value.isEmpty ?? false)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.confirm),
            child: const Text('Leave'),
          ),
      ],
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.groupId,
    required this.member,
    required this.isMe,
    required this.iAmOwner,
    required this.iCanManage,
  });

  final String groupId;
  final GroupMember member;
  final bool isMe;
  final bool iAmOwner;
  final bool iCanManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the owner may touch the owner or hand ownership over.
    final canManageThisMember =
        iCanManage && !isMe && (iAmOwner || !member.isOwner);

    return ListTile(
      leading: UserAvatar(
        displayName: member.displayName,
        avatarPath: member.avatarPath,
        semanticsSuffix: member.roleLabel,
      ),
      title: Text(isMe ? '${member.displayName} (you)' : member.displayName),
      subtitle: Text(member.roleLabel),
      trailing: canManageThisMember
          ? PopupMenuButton<String>(
              tooltip: 'Manage ${member.displayName}',
              onSelected: (value) => _act(context, ref, value),
              itemBuilder: (_) => [
                if (iAmOwner && !member.isOwner)
                  const PopupMenuItem(
                    value: 'owner',
                    child: Text('Make owner'),
                  ),
                if (!member.isAdmin && !member.isOwner)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Text('Make admin'),
                  ),
                if (member.isAdmin)
                  const PopupMenuItem(
                    value: 'member',
                    child: Text('Make member'),
                  ),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            )
          : null,
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    // Captured before any await: these actions invalidate the member list,
    // which disposes this tile and its ref.
    final actions = ref.read(groupActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Remove ${member.displayName}?'),
          content: const Text(
            'They lose access to this group. Their past bills stay as they are.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final ok = await actions.removeMember(
        groupId: groupId,
        userId: member.userId,
      );
      if (!ok) _showError(messenger, actions);
      return;
    }

    if (action == 'owner') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Make ${member.displayName} the owner?'),
          content: const Text(
            "You'll become an admin. Only one person can own a group.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hand over'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final ok = await actions.setRole(
      groupId: groupId,
      userId: member.userId,
      role: action,
    );
    if (!ok) _showError(messenger, actions);
  }

  void _showError(ScaffoldMessengerState messenger, GroupActions actions) {
    messenger.showSnackBar(
      SnackBar(content: Text(actions.lastError ?? 'That did not work.')),
    );
  }
}
