import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/images/attachment_storage.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/images/image_service.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/payment_methods_repository.dart';
import '../../domain/payment_method.dart';

/// Profile → Payment methods (spec §9).
///
/// What a debtor sees when they tap Settle up, so it is worth keeping exact.
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionStateProvider).userId;
    if (userId == null) return const SizedBox.shrink();

    final methods = ref.watch(paymentMethodsForProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, userId, null),
        icon: const Icon(Icons.add),
        label: const Text('Add method'),
      ),
      body: methods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load your payment methods.',
          onRetry: () => ref.invalidate(paymentMethodsForProvider(userId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No payment methods yet',
              message:
                  'Add your GCash, Maya, GoTyme, ShopeePay or other wallet '
                  'QR codes so your barkada can scan and pay you.',
              actionLabel: 'Add method',
              actionIcon: Icons.add,
              onAction: () => _edit(context, ref, userId, null),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                      child: Text(
                        'Add one for each wallet you use, with its QR code.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _PreferredWallet(userId: userId, methods: list),
                    const SectionHeader('Your wallets'),
                    ListGroup(
                      dividerIndent: 56,
                      children: [
                        for (final method in list)
                          ListTile(
                            leading: Icon(
                              method.hasQr
                                  ? Icons.qr_code_2
                                  : Icons.account_balance_wallet_outlined,
                              semanticLabel: method.hasQr
                                  ? 'Has a QR code'
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(method.displayLabel)),
                                if (method.isDefault) ...[
                                  const SizedBox(width: kSpace),
                                  const Tag('Default'),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${method.accountName}\n${method.accountNumber}'
                              '${method.hasQr ? '' : ' · no QR yet'}',
                            ),
                            isThreeLine: true,
                            onTap: () => _edit(context, ref, userId, method),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                final actions = ref.read(
                                  paymentMethodActionsProvider.notifier,
                                );
                                if (value == 'default') {
                                  await actions.makeDefault(
                                    userId: userId,
                                    id: method.id,
                                  );
                                } else if (value == 'delete') {
                                  await _confirmDelete(
                                    context,
                                    ref,
                                    userId,
                                    method,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                if (!method.isDefault)
                                  const PopupMenuItem(
                                    value: 'default',
                                    child: Text('Make default'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String userId,
    PaymentMethod method,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${method.displayLabel}?'),
        content: const Text(
          'Your barkada will no longer see these details when they settle up.',
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

    await ref
        .read(paymentMethodActionsProvider.notifier)
        .remove(userId: userId, id: method.id);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String userId,
    PaymentMethod? existing,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MethodForm(userId: userId, existing: existing),
    );
  }
}

class _MethodForm extends ConsumerStatefulWidget {
  const _MethodForm({required this.userId, required this.existing});

  final String userId;
  final PaymentMethod? existing;

  @override
  ConsumerState<_MethodForm> createState() => _MethodFormState();
}

class _MethodFormState extends ConsumerState<_MethodForm> {
  final _formKey = GlobalKey<FormState>();
  late final _accountName = TextEditingController(
    text: widget.existing?.accountName ?? '',
  );
  late final _accountNumber = TextEditingController(
    text: widget.existing?.accountNumber ?? '',
  );
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late PaymentMethodType _type =
      widget.existing?.kind ?? PaymentMethodType.gcash;
  late bool _isDefault = widget.existing?.isDefault ?? false;
  late String? _qrPath = widget.existing?.qrImagePath;
  PickedImage? _pendingQr;
  String? _error;

  @override
  void dispose() {
    _accountName.dispose();
    _accountNumber.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentMethodActionsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'Add method' : 'Edit method',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: kSpace * 2),

                Wrap(
                  spacing: kSpace,
                  runSpacing: kSpace / 2,
                  children: [
                    for (final type in PaymentMethodType.values)
                      ChoiceChip(
                        label: Text(type.label),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: kSpace * 2),

                TextFormField(
                  controller: _accountName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                    hintText: 'Bea Reyes',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? "Whose account is it?"
                      : null,
                ),
                const SizedBox(height: kSpace * 2),
                TextFormField(
                  controller: _accountNumber,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: !_type.isEWallet && _type != PaymentMethodType.other
                        ? 'Account number'
                        : 'Mobile number',
                    hintText: !_type.isEWallet && _type != PaymentMethodType.other
                        ? '1234 5678 90'
                        : '0917 123 4567',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Add the number' : null,
                ),
                const SizedBox(height: kSpace * 2),
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    helperText: 'Optional — e.g. "BPI Savings"',
                  ),
                ),
                const SizedBox(height: kSpace),
                SwitchListTile(
                  value: _isDefault,
                  onChanged: (value) => setState(() => _isDefault = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use as my default'),
                ),

                const SizedBox(height: kSpace),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'QR code',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: kSpace / 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _type.isEWallet
                        ? 'In ${_type.label}, open your "Receive" QR and save '
                              'a screenshot of it.'
                        : 'A screenshot of the QR your bank gives you to '
                              'receive money (QR Ph works with most wallets).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: kSpace),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _QrPreview(
                    pending: _pendingQr,
                    existingPath: _qrPath,
                    onPick: _pickQr,
                    onRemove: () => setState(() {
                      _pendingQr = null;
                      _qrPath = null;
                    }),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: kSpace * 2),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],

                const SizedBox(height: kSpace * 2),
                FilledButton(
                  onPressed: state.isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickQr() async {
    final source = await askImageSource(context);
    if (source == null || !mounted) return;

    final picked = await ref.read(imageServiceProvider).pick(source);
    if (picked == null || !mounted) return;

    setState(() => _pendingQr = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The QR goes up first: the method row stores its path, so the object has
    // to exist before the row references it.
    var qrPath = _qrPath;
    if (_pendingQr != null) {
      final storage = ref.read(attachmentStorageProvider);
      qrPath = StoragePaths.paymentQr(widget.userId, storage.newFilename());
      try {
        await storage.upload(
          bucket: StorageBucket.paymentQr,
          path: qrPath,
          image: _pendingQr!,
        );
      } on AttachmentFailure catch (failure) {
        if (!mounted) return;
        setState(() => _error = 'Could not upload the QR: ${failure.message}');
        return;
      }
    }

    final method = PaymentMethod(
      id: widget.existing?.id ?? '',
      userId: widget.userId,
      type: _type.wire,
      accountName: _accountName.text.trim(),
      accountNumber: _accountNumber.text.trim(),
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      qrImagePath: qrPath,
      isDefault: _isDefault,
    );

    final ok = await ref
        .read(paymentMethodActionsProvider.notifier)
        .save(method);
    if (ok && mounted) Navigator.of(context).pop();
  }
}

/// The QR slot on the method form: pick one, or show what is already saved.
class _QrPreview extends StatelessWidget {
  const _QrPreview({
    required this.pending,
    required this.existingPath,
    required this.onPick,
    required this.onRemove,
  });

  final PickedImage? pending;
  final String? existingPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (pending != null) {
      return PendingImageThumb(
        bytes: pending!.bytes,
        onRemove: onRemove,
        size: 120,
      );
    }

    if (existingPath != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusMd),
            child: AttachmentImage(
              bucket: StorageBucket.paymentQr,
              path: existingPath!,
              width: 120,
              height: 120,
              fit: BoxFit.contain,
              enlargeOnTap: false,
              semanticLabel: 'Your saved QR code',
            ),
          ),
          const SizedBox(width: kSpace),
          TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.qr_code_2),
      label: const Text('Add QR screenshot'),
    );
  }
}


/// "Ask people to pay you via" — the default every bill uses unless it says
/// otherwise (DECISIONS D-66).
class _PreferredWallet extends ConsumerWidget {
  const _PreferredWallet({required this.userId, required this.methods});

  final String userId;
  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preferred =
        ref.watch(preferredReceiveMethodProvider(userId)).asData?.value;
    final current = methods.any((m) => m.id == preferred) ? preferred : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownMenu<String?>(
          key: ValueKey('preferred-$current'),
          expandedInsets: EdgeInsets.zero,
          initialSelection: current,
          label: const Text('Ask people to pay you via'),
          leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
          onSelected: (id) {
            if (id == current) return;
            ref
                .read(paymentMethodActionsProvider.notifier)
                .setPreferred(userId: userId, methodId: id);
          },
          dropdownMenuEntries: [
            const DropdownMenuEntry<String?>(
              value: null,
              label: 'Any of my wallets',
            ),
            for (final method in methods)
              DropdownMenuEntry<String?>(
                value: method.id,
                label: method.displayLabel,
              ),
          ],
        ),
        const SizedBox(height: kSpace),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            current == null
                ? 'People settling up can use any wallet you have added.'
                : 'People settling up see only this one — unless you choose '
                    'a different wallet on a particular bill.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
