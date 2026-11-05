import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/comment.dart';
import '../activity_controller.dart';

/// The comment thread at the bottom of Bill detail (spec §10).
class CommentThread extends ConsumerStatefulWidget {
  const CommentThread({
    required this.billId,
    required this.currentUserId,
    super.key,
  });

  final String billId;
  final String currentUserId;

  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
  final _composer = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onChanged);
  }

  void _onChanged() {
    final canSend = _composer.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);
  }

  @override
  void dispose() {
    _composer
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comments = ref.watch(billCommentsProvider(widget.billId));
    final actionState = ref.watch(commentActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Comments',
          padding: EdgeInsets.fromLTRB(4, 0, 4, kSpace),
        ),

        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => ErrorRetry(
            message: 'Could not load the comments.',
            onRetry: () => ref.invalidate(billCommentsProvider(widget.billId)),
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: kSpace * 2),
                  child: Text(
                    'No comments yet. Ask a question, or say thanks.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final comment in list)
                      _CommentRow(
                        comment: comment,
                        isMine: comment.authorId == widget.currentUserId,
                        billId: widget.billId,
                      ),
                  ],
                ),
        ),

        const SizedBox(height: kSpace * 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a comment',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: kSpace),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _canSend && !actionState.isLoading ? _send : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _send() async {
    final actions = ref.read(commentActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final body = _composer.text.trim();

    final ok = await actions.add(billId: widget.billId, body: body);
    if (!mounted) return;

    if (ok) {
      _composer.clear();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(actions.lastError ?? 'Could not post that.')),
      );
    }
  }
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({
    required this.comment,
    required this.isMine,
    required this.billId,
  });

  final Comment comment;
  final bool isMine;
  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace * 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            displayName: comment.author,
            avatarPath: comment.authorAvatarPath,
            radius: 16,
          ),
          const SizedBox(width: kSpace * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isMine ? 'You' : comment.author,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(width: kSpace),
                    Text(
                      DateFormat.MMMd(
                        'en_PH',
                      ).add_jm().format(comment.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (comment.wasEdited) ...[
                      const SizedBox(width: kSpace / 2),
                      Text(
                        '(edited)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: kSpace / 2),
                Text(
                  comment.displayBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: comment.isDeleted
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: comment.isDeleted
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (isMine && !comment.isDeleted)
            PopupMenuButton<String>(
              tooltip: 'Comment options',
              onSelected: (value) =>
                  value == 'edit' ? _edit(context, ref) : _delete(context, ref),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(commentActionsProvider.notifier);
    final controller = TextEditingController(text: comment.body);

    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 1000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (body == null || body.isEmpty || body == comment.body) return;
    await actions.edit(billId: billId, commentId: comment.id, body: body);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(commentActionsProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this comment?'),
        content: const Text(
          "The thread keeps its place, but nobody will see what you wrote.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await actions.remove(billId: billId, commentId: comment.id);
  }
}
