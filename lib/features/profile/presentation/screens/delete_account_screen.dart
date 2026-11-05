import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../data/account_repository.dart';

/// Profile → Delete account (DECISIONS D-64).
///
/// Says plainly what goes and what stays, refuses while money is open, and
/// asks for the word DELETE — this cannot be undone.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accountRepositoryProvider).deleteAccount();
      // Signing out sends the router to Welcome; this outlives the screen.
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } on AccountDeletionFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = failure.message;
      });
      ref.invalidate(deletionBlockersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockers = ref.watch(deletionBlockersProvider);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This permanently deletes your Hati account.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: kSpace * 2),
                const SectionHeader(
                  'Deleted',
                  padding: EdgeInsets.fromLTRB(4, 0, 4, kSpace),
                ),
                const _Points([
                  'Your sign-in, profile photo, and settings',
                  'Your payment methods and QR codes',
                  'Your notifications and devices',
                ]),
                const SectionHeader('Kept for your groups, without your name'),
                const _Points([
                  'Bills, payments, receipts and comments you shared — the '
                      'other members need them for their own records. They '
                      'show "Deleted user" instead of your name.',
                ]),
                const SizedBox(height: kSpace * 3),

                blockers.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(kSpace * 2),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, _) => ErrorRetry(
                    message: 'Could not check your open bills.',
                    onRetry: () => ref.invalidate(deletionBlockersProvider),
                  ),
                  data: (open) => open.isEmpty
                      ? _Confirm(
                          controller: _confirm,
                          deleting: _deleting,
                          error: _error,
                          onDelete: _delete,
                        )
                      : _Blocked(blockers: open, muted: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Points extends StatelessWidget {
  const _Points(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: style),
                  Expanded(child: Text(item, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Open money: nothing to confirm yet, only what to settle.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.blockers, required this.muted});

  final List<DeletionBlocker> blockers;
  final TextStyle? muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoNote(
          icon: Icons.lock_clock_outlined,
          message: 'Settle these first. Deleting now would leave people '
              'without a way to pay you, or with debts no one can collect.',
        ),
        const SectionHeader('Still open'),
        ListGroup(
          children: [
            for (final blocker in blockers)
              ListTile(
                title: Text(blocker.title),
                subtitle: Text(
                  '${blocker.groupName} · '
                  '${blocker.youOwe ? 'you owe' : 'owed to you'}',
                ),
                trailing: AmountText(
                  blocker.amount,
                  style: theme.textTheme.titleSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.controller,
    required this.deleting,
    required this.error,
    required this.onDelete,
  });

  final TextEditingController controller;
  final bool deleting;
  final String? error;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = controller.text.trim() == 'DELETE' && !deleting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: !deleting,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Type DELETE to confirm',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: kSpace * 1.5),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: kSpace * 2),
        FilledButton(
          onPressed: ready ? onDelete : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: const Size.fromHeight(50),
          ),
          child: deleting
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onError,
                  ),
                )
              : const Text('Delete my account'),
        ),
        const SizedBox(height: kSpace),
        Text(
          "This can't be undone.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
