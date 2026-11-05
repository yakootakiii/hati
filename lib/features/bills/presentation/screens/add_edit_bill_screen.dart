import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/images/image_service.dart';
import '../../../../core/split/split.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../groups/domain/group_models.dart';
import '../../domain/bill_models.dart';
import '../../../groups/presentation/groups_controller.dart';
import '../bill_form_controller.dart';
import '../bills_controller.dart';
import '../widgets/itemized_editor.dart';
import '../widgets/split_section.dart';

/// Add / Edit bill (spec §10).
class AddEditBillScreen extends ConsumerWidget {
  const AddEditBillScreen({required this.groupId, this.billId, super.key});

  final String groupId;

  /// Null when adding.
  final String? billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionStateProvider).userId;
    final members = ref.watch(groupMembersProvider(groupId));

    if (userId == null) return const SizedBox.shrink();

    return members.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(
          message: 'Could not load the group members.',
          onRetry: () => ref.invalidate(groupMembersProvider(groupId)),
        ),
      ),
      data: (list) => _Form(
        groupId: groupId,
        billId: billId,
        currentUserId: userId,
        members: list,
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({
    required this.groupId,
    required this.billId,
    required this.currentUserId,
    required this.members,
  });

  final String groupId;
  final String? billId;
  final String currentUserId;
  final List<GroupMember> members;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  bool _seeded = false;
  String? _serverError;
  final List<PickedImage> _receipts = <PickedImage>[];
  String? _uploadProgress;

  /// Spec §12.11.
  static const int maxReceipts = 5;

  BillForm get _controller => ref.read(
        billFormProvider(
          groupId: widget.groupId,
          currentUserId: widget.currentUserId,
        ).notifier,
      );

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Fills the form once: from the existing bill when editing, or with
  /// everyone selected when adding, which is what people want nearly every
  /// time.
  void _seed(Bill? existing) {
    if (_seeded) return;
    _seeded = true;

    if (existing != null) {
      _controller.loadFrom(existing);
      _titleController.text = existing.title;
      _notesController.text = existing.notes ?? '';
    } else {
      _controller.selectAll(widget.members.map((m) => m.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = (groupId: widget.groupId, currentUserId: widget.currentUserId);
    final form = ref.watch(billFormProvider(
      groupId: args.groupId,
      currentUserId: args.currentUserId,
    ));
    final actionState = ref.watch(billActionsProvider);

    if (widget.billId != null) {
      final existing = ref.watch(billDetailProvider(widget.billId!));
      if (existing.hasValue) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _seed(existing.value));
      }
      if (existing.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _seed(null));
    }

    final preview = previewSplit(form, widget.members);
    final canSave = form.title.trim().isNotEmpty &&
        preview.result != null &&
        !actionState.isLoading;
    final serverError = _serverError;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.isEditing ? 'Edit bill' : 'Add bill'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: kPagePadding,
          child: FilledButton(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: actionState.isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      if (_uploadProgress != null) ...[
                        const SizedBox(width: kSpace * 1.5),
                        Text(_uploadProgress!),
                      ],
                    ],
                  )
                : Text(form.isEditing ? 'Save changes' : 'Add bill'),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: kPagePadding,
          children: [
            if (serverError != null) ...[
              Container(
                padding: const EdgeInsets.all(kSpace * 1.5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer, size: 20),
                    const SizedBox(width: kSpace * 1.5),
                    Expanded(
                      child: Text(
                        serverError,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kSpace * 2),
            ],

            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'Airbnb – 2 nights',
              ),
              onChanged: _controller.setTitle,
            ),

            AmountField(
              label: 'Total',
              initial: form.total,
              enabled: form.mode != SplitMode.itemized,
              helperText: form.mode == SplitMode.itemized
                  ? 'Worked out from the items below'
                  : null,
              onChanged: _controller.setTotal,
            ),
            const SizedBox(height: kSpace * 2),

            // Stacked rather than side by side: at phone width and 200% text
            // the two fields together have nowhere to go.
            _DateField(date: form.billDate, onChanged: _controller.setDate),
            const SizedBox(height: kSpace * 2),
            DropdownButtonFormField<String>(
              initialValue: form.paidBy,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [
                for (final member in canonicalMemberOrder(widget.members))
                  DropdownMenuItem(
                    value: member.userId,
                    child: Text(
                      member.userId == widget.currentUserId
                          ? 'Me'
                          : member.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _controller.setPaidBy(value);
              },
            ),
            const SizedBox(height: kSpace * 2),

            DropdownButtonFormField<String>(
              initialValue: form.category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: null, child: Text('None')),
                DropdownMenuItem(value: 'lodging', child: Text('Lodging')),
                DropdownMenuItem(value: 'food', child: Text('Food')),
                DropdownMenuItem(value: 'transport', child: Text('Transport')),
                DropdownMenuItem(value: 'utilities', child: Text('Utilities')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _controller.setCategory,
            ),
            const SizedBox(height: kSpace * 2),

            TextField(
              controller: _notesController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
              onChanged: _controller.setNotes,
            ),

            const Divider(height: kSpace * 5),
            _ReceiptsRow(
              receipts: _receipts,
              progress: _uploadProgress,
              onAdd: _addReceipt,
              onRemove: (index) => setState(() => _receipts.removeAt(index)),
              max: maxReceipts,
            ),

            const Divider(height: kSpace * 5),

            SplitSection(
              groupId: widget.groupId,
              currentUserId: widget.currentUserId,
              members: widget.members,
            ),

            if (form.mode == SplitMode.itemized) ...[
              const Divider(height: kSpace * 5),
              ItemizedEditor(
                groupId: widget.groupId,
                currentUserId: widget.currentUserId,
                members: widget.members,
              ),
            ],

            const SizedBox(height: kSpace * 4),
          ],
        ),
      ),
    );
  }

  Future<void> _addReceipt() async {
    if (_receipts.length >= maxReceipts) return;

    final source = await askImageSource(context);
    if (source == null || !mounted) return;

    final picked = await ref.read(imageServiceProvider).pick(source);
    if (picked == null || !mounted) return;

    setState(() => _receipts.add(picked));
  }

  Future<void> _save() async {
    final form = ref.read(billFormProvider(
      groupId: widget.groupId,
      currentUserId: widget.currentUserId,
    ));
    final draft = buildDraft(form, widget.members);
    if (draft == null) return;

    final actions = ref.read(billActionsProvider.notifier);

    // Spec §12.11: the save waits for the uploads.
    void progress(int done, int total) {
      if (mounted) {
        setState(() => _uploadProgress = 'Uploading receipt $done of $total');
      }
    }

    if (form.isEditing) {
      final ok = await actions.edit(form.editingBillId!, draft);
      if (ok && _receipts.isNotEmpty) {
        await actions.addReceipts(
          billId: form.editingBillId!,
          groupId: draft.groupId,
          receipts: _receipts,
          onProgress: progress,
        );
      }
      if (!mounted) return;
      setState(() => _uploadProgress = null);
      if (ok) {
        context.pop();
      } else {
        setState(() => _serverError = actions.lastError);
      }
      return;
    }

    final id = await actions.createWithReceipts(
      draft: draft,
      receipts: _receipts,
      onProgress: progress,
    );
    if (!mounted) return;
    setState(() => _uploadProgress = null);
    if (id != null) {
      context.pushReplacement('/bills/$id');
    } else {
      setState(() => _serverError = actions.lastError);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Text(DateFormat.yMMMd('en_PH').format(date)),
      ),
    );
  }
}


/// Receipt photos for the bill (spec §10, §12.11).
class _ReceiptsRow extends StatelessWidget {
  const _ReceiptsRow({
    required this.receipts,
    required this.progress,
    required this.onAdd,
    required this.onRemove,
    required this.max,
  });

  final List<PickedImage> receipts;
  final String? progress;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text('Receipts', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(width: kSpace),
            Flexible(
              child: Text(
                '${receipts.length} of $max',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: kSpace * 1.5),
        Wrap(
          spacing: kSpace * 1.5,
          runSpacing: kSpace * 1.5,
          children: [
            for (var i = 0; i < receipts.length; i++)
              PendingImageThumb(
                bytes: receipts[i].bytes,
                onRemove: () => onRemove(i),
              ),
            if (receipts.length < max)
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(kRadiusMd),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusMd),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
              ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: kSpace),
          Text(progress!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
