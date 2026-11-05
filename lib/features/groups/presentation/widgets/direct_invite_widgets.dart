import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';

/// Join / Decline for an invite sent by name (DECISIONS D-57). Shared by the
/// notification row and the card on the Groups tab, so both answer the same
/// way.
class InviteResponseButtons extends ConsumerStatefulWidget {
  const InviteResponseButtons({
    required this.inviteId,
    required this.groupName,
    super.key,
  });

  final String inviteId;
  final String groupName;

  @override
  ConsumerState<InviteResponseButtons> createState() =>
      _InviteResponseButtonsState();
}

class _InviteResponseButtonsState extends ConsumerState<InviteResponseButtons> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : () => _answer(accept: true),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Join'),
          ),
        ),
        const SizedBox(width: kSpace * 1.5),
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => _answer(accept: false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Decline'),
          ),
        ),
      ],
    );
  }

  Future<void> _answer({required bool accept}) async {
    setState(() => _busy = true);
    // Captured before the await: answering invalidates the lists that built
    // this widget, so it may be gone by the time the call returns.
    final actions = ref.read(groupActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final groupId = await actions.respondToInvite(
      widget.inviteId,
      accept: accept,
    );

    if (mounted) setState(() => _busy = false);

    if (groupId == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'Something went wrong.')),
      );
    } else if (accept) {
      messenger.showSnackBar(
        SnackBar(content: Text('You joined ${widget.groupName}')),
      );
      await router.push(Routes.groupDetail(groupId));
    }
  }
}

/// A pending invite at the top of the Groups tab, so it is not lost if the
/// notification scrolls away.
class DirectInviteCard extends StatelessWidget {
  const DirectInviteCard({required this.invite, super.key});

  final DirectInvite invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberWord = invite.memberCount == 1 ? 'member' : 'members';

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.group_add_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: kSpace * 1.5),
                Expanded(
                  child: Text(
                    '${invite.inviterName} invited you to ${invite.groupName}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpace / 2),
            Padding(
              padding: const EdgeInsets.only(left: 24 + kSpace * 1.5),
              child: Text(
                '${invite.memberCount} $memberWord',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: kSpace * 2),
            InviteResponseButtons(
              inviteId: invite.id,
              groupName: invite.groupName,
            ),
          ],
        ),
      ),
    );
  }
}
