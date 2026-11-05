import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';
import '../join_controller.dart';

/// The invite landing screen (spec §8.2–8.4).
class JoinGroupScreen extends ConsumerWidget {
  const JoinGroupScreen({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(invitePreviewProvider(token));

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: kPagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: preview.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _Unusable(
                  message: 'Could not check that link. Try again.',
                  onDismiss: () => ref.invalidate(invitePreviewProvider(token)),
                  dismissLabel: 'Retry',
                ),
                data: (result) => switch (result) {
                  ValidInvitePreview(:final groupName) => _Invitation(
                    token: token,
                    preview: result,
                    groupName: groupName,
                  ),
                  InvalidInvitePreview(:final reason) => _Unusable(
                    message: _reasonCopy(reason),
                    onDismiss: () => context.go(Routes.groups),
                    dismissLabel: 'Back to groups',
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _reasonCopy(InviteInvalidReason reason) => switch (reason) {
    InviteInvalidReason.expired =>
      'That invite link has expired. Ask for a new one.',
    InviteInvalidReason.revoked =>
      'That invite link was reset. Ask for a new one.',
    InviteInvalidReason.exhausted =>
      'That invite link has been used up. Ask for a new one.',
    InviteInvalidReason.notFound =>
      "That invite link isn't valid. Ask for a new one.",
  };
}

class _Invitation extends ConsumerWidget {
  const _Invitation({
    required this.token,
    required this.preview,
    required this.groupName,
  });

  final String token;
  final ValidInvitePreview preview;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(joinControllerProvider);
    final inviter = preview.inviterName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.groups, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: kSpace * 3),
        Text(
          groupName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: kSpace),
        Text(
          [
            if (inviter != null) '$inviter invited you.',
            '${preview.memberCount} '
                '${preview.memberCount == 1 ? 'member' : 'members'} so far.',
          ].join(' '),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: kSpace * 4),
        if (state.hasError) ...[
          Text(
            groupErrorMessage(state) ?? 'Could not join.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: kSpace * 2),
        ],
        FilledButton(
          onPressed: state.isLoading ? null : () => _join(context, ref),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: state.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(preview.alreadyMember ? 'Open group' : 'Join group'),
        ),
        const SizedBox(height: kSpace),
        TextButton(
          onPressed: () => context.go(Routes.groups),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final groupId = await ref.read(joinControllerProvider.notifier).join(token);
    if (groupId != null && context.mounted) {
      context.go(Routes.groupDetail(groupId));
    }
  }
}

class _Unusable extends StatelessWidget {
  const _Unusable({
    required this.message,
    required this.onDismiss,
    required this.dismissLabel,
  });

  final String message;
  final VoidCallback onDismiss;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.link_off,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: kSpace * 3),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: kSpace * 4),
        FilledButton(
          onPressed: onDismiss,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(dismissLabel),
        ),
      ],
    );
  }
}
