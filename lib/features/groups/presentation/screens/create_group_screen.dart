import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../groups_controller.dart';
import '../widgets/invite_sheet.dart';

/// Name the group, then go straight to the invite sheet (spec §10).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _name.text.trim();
    final id = await ref
        .read(groupActionsProvider.notifier)
        .createGroup(name: name);

    if (!mounted) return;
    if (id == null) {
      setState(
        () => _error = ref.read(groupActionsProvider.notifier).lastError,
      );
      return;
    }

    // Replace, so Back from the group goes to the list rather than this form.
    context.pushReplacement(Routes.groupDetail(id));
    await InviteSheet.show(context, groupId: id, groupName: name);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupActionsProvider);
    final message = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: kPagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null) ...[
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: kSpace * 2),
                ],
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'Tagaytay Staycation',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Give the group a name'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: kSpace * 3),
                FilledButton(
                  onPressed: state.isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: state.isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create group'),
                ),
                const SizedBox(height: kSpace),
                Text(
                  'A photo can be added later, in group settings.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
