import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/group_models.dart';
import '../groups_controller.dart';

/// Invite people: search for someone on Hati and invite them directly
/// (DECISIONS D-57), or share the link (spec §8) — Copy, Share, and Reset,
/// which revokes the old token as it mints a new one.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({
    required this.groupId,
    required this.groupName,
    super.key,
  });

  final String groupId;
  final String groupName;

  static Future<void> show(
    BuildContext context, {
    required String groupId,
    required String groupName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InviteSheet(groupId: groupId, groupName: groupName),
    );
  }

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invite = ref.watch(activeInviteProvider(widget.groupId));
    final busy = ref.watch(groupActionsProvider).isLoading;

    // Scrolls, because the keyboard and a page of results together do not fit
    // a small phone (D-53).
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invite to ${widget.groupName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: kSpace * 2),
            _PeopleSearch(groupId: widget.groupId),
            const SizedBox(height: kSpace * 3),
            const Divider(height: 1),
            const SizedBox(height: kSpace * 2),
            Text('Or share a link', style: theme.textTheme.titleSmall),
            const SizedBox(height: kSpace),
            Text(
              'Anyone with this link can join. Reset it any time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace * 3),
            invite.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => _Actions(
                label: 'Create a link',
                onPressed: busy ? null : () => _mint(reset: false),
              ),
              data: (link) => link == null
                  ? _Actions(
                      label: 'Create a link',
                      onPressed: busy ? null : () => _mint(reset: false),
                    )
                  : _LinkBody(
                      link: link,
                      busy: busy,
                      onReset: () => _mint(reset: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mint({required bool reset}) async {
    final link = await ref
        .read(groupActionsProvider.notifier)
        .createInvite(widget.groupId, reset: reset);

    if (!mounted) return;
    if (link == null) {
      final message = groupErrorMessage(ref.read(groupActionsProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Could not create the link.')),
      );
    } else if (reset) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link reset — the old one no longer works.'),
        ),
      );
    }
  }
}

class _LinkBody extends StatelessWidget {
  const _LinkBody({
    required this.link,
    required this.busy,
    required this.onReset,
  });

  final InviteLink link;
  final bool busy;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(kSpace * 1.5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: SelectableText(link.url, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: kSpace * 2),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link.url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(width: kSpace * 1.5),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: link.url, subject: 'Join my group on Hati'),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: kSpace),
        TextButton.icon(
          onPressed: busy ? null : onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset link'),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(label),
    );
  }
}

/// Find someone already on Hati by name, or by exact email when several share
/// a name, and invite them straight into the group (DECISIONS D-57).
class _PeopleSearch extends ConsumerStatefulWidget {
  const _PeopleSearch({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_PeopleSearch> createState() => _PeopleSearchState();
}

class _PeopleSearchState extends ConsumerState<_PeopleSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// Rows with a call in flight, so a double tap sends one invite.
  final Set<String> _busy = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.length >= 2;
    final results = searching
        ? ref.watch(peopleSearchProvider(widget.groupId, _query))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Find people on Hati',
            hintText: 'Name, or their exact email',
            border: OutlineInputBorder(),
          ),
        ),
        if (results != null)
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: kSpace * 2),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => _Hint(
              text: "Couldn't search right now. Try again.",
              color: theme.colorScheme.error,
            ),
            data: (people) => people.isEmpty
                ? const _Hint(
                    text:
                        'No one by that name. If several people share a '
                        'name, try their email — they need a Hati account.',
                  )
                : Column(
                    children: [
                      for (final person in people) _personTile(person),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _personTile(PersonResult person) {
    final busy = _busy.contains(person.id);

    final Widget? trailing;
    if (person.isMember) {
      trailing = null;
    } else if (person.isPending) {
      trailing = TextButton(
        onPressed: busy ? null : () => _cancel(person),
        child: const Text('Cancel'),
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: busy ? null : () => _invite(person),
        child: const Text('Invite'),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(displayName: person.displayName),
      title: Text(person.displayName),
      subtitle: person.isMember
          ? const Text('Already in the group')
          : person.isPending
          ? const Text('Invite sent')
          : null,
      trailing: trailing,
    );
  }

  Future<void> _invite(PersonResult person) => _act(
    person,
    (actions) =>
        actions.invitePerson(groupId: widget.groupId, userId: person.id),
    done: 'Invited ${person.displayName}',
  );

  Future<void> _cancel(PersonResult person) => _act(
    person,
    (actions) => actions.cancelDirectInvite(person.inviteId!),
    done: 'Invite to ${person.displayName} cancelled',
  );

  Future<void> _act(
    PersonResult person,
    Future<bool> Function(GroupActions actions) call, {
    required String done,
  }) async {
    setState(() => _busy.add(person.id));
    final actions = ref.read(groupActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await call(actions);

    if (mounted) setState(() => _busy.remove(person.id));
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? done : actions.lastError ?? 'Something went wrong.'),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: kSpace * 1.5),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
