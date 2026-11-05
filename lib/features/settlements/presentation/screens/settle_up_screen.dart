import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/images/attachment_storage.dart';
import '../../../../core/images/image_gallery.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/images/image_service.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../bills/domain/bill_models.dart';
import '../../../profile/data/payment_methods_repository.dart';
import '../../../profile/domain/payment_method.dart';
import '../settlements_controller.dart';
import '../widgets/wallet_launcher.dart';

/// Settle up (spec §9).
///
/// A full page rather than a sheet: a QR has to be big enough to scan from
/// another phone, and the proof step needs room.
///
/// 1. How to pay: the wallet the payer asked for (bill.receiveMethodId), or a
///    choice between all of their wallets when they left it open.
/// 2. Proof: a screenshot of the receipt. "I've paid" stays disabled until
///    one is attached; the RPC enforces the same rule (HT047).
///
/// Or Cash: no QR and no screenshot — the payer confirms once they have the
/// money (D-70).
/// One share to settle: the bill and the caller's part of it.
class SettleItem {
  const SettleItem(this.bill, this.share);

  final Bill bill;
  final BillShare share;
}

class SettleUpScreen extends ConsumerStatefulWidget {
  const SettleUpScreen({
    required this.items,
    required this.payerName,
    super.key,
  }) : assert(items.length > 0, 'nothing to settle');

  /// One bill, or several owed to the same person in one group — settled
  /// with one payment and one screenshot (DECISIONS D-67).
  final List<SettleItem> items;
  final String payerName;

  static Future<void> show(
    BuildContext context, {
    required Bill bill,
    required BillShare share,
    required String payerName,
  }) =>
      showAll(context, items: [SettleItem(bill, share)], payerName: payerName);

  static Future<void> showAll(
    BuildContext context, {
    required List<SettleItem> items,
    required String payerName,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettleUpScreen(items: items, payerName: payerName),
      ),
    );
  }

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  final _referenceController = TextEditingController();

  /// The wallet card on show when the payer allows any of their wallets.
  String? _selectedMethodId;

  /// How the debtor says they paid, when the payer has no methods to pick
  /// from. Otherwise it follows the wallet on show.
  PaymentMethodType? _manualMethod;

  PickedImage? _proof;
  String? _error;

  /// Paying cash in person: no QR, no screenshot (D-70).
  bool _cash = false;

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payerId = widget.items.first.bill.paidBy;
    final methods = ref.watch(paymentMethodsForProvider(payerId));
    // Where they asked to be paid by default (D-66); a bill's own choice wins.
    _preferred = ref
        .watch(preferredReceiveMethodProvider(payerId))
        .asData
        ?.value;
    final total = Money(
      widget.items.fold(0, (sum, i) => sum + i.share.amount.centavos),
    );
    final titles = widget.items.map((i) => i.bill.title).join(', ');
    final isSubmitting = ref.watch(settlementActionsProvider).isLoading;
    final list = methods.asData?.value ?? const <PaymentMethod>[];
    final shown = _shownMethod(list);
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: SafeArea(
        child: ListView(
          padding: kPagePadding,
          children: [
            Text(
              'You owe ${widget.payerName}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: kSpace / 2),
            AmountText(
              total,
              style: theme.textTheme.displaySmall,
              color: context.money.owe,
            ),
            const SizedBox(height: kSpace / 2),
            Text(
              widget.items.length == 1
                  ? titles
                  : '${widget.items.length} bills · $titles',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: kSpace * 3),
            // Wallet and bank payments need a screenshot; cash cannot have
            // one, so it gets its own path (D-70).
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.qr_code_2, size: 18),
                  label: Text('Wallet or bank'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.payments_outlined, size: 18),
                  label: Text('Cash'),
                ),
              ],
              selected: {_cash},
              showSelectedIcon: false,
              onSelectionChanged: (choice) => setState(() {
                _cash = choice.single;
                _error = null;
              }),
            ),

            if (_cash) ...[
              const SizedBox(height: kSpace * 3),
              InfoNote(
                icon: Icons.handshake_outlined,
                message:
                    'Hand the cash to ${widget.payerName}, then tap '
                    '"I paid in cash". They confirm once they have it — '
                    'until then it shows as awaiting confirmation.',
              ),
            ] else ...[
              const SizedBox(height: kSpace * 3),
              _StepHeading(number: 1, title: 'Pay ${widget.payerName}'),
              const SizedBox(height: kSpace * 1.5),
              methods.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => _NoMethods(payerName: widget.payerName),
                data: (list) => list.isEmpty
                    ? _NoMethods(payerName: widget.payerName)
                    : _HowToPay(
                        methods: list,
                        shown: shown!,
                        pinned: _pinned(list) != null,
                        payerName: widget.payerName,
                        onSelect: (id) =>
                            setState(() => _selectedMethodId = id),
                      ),
              ),

              const SizedBox(height: kSpace * 4),
              const _StepHeading(number: 2, title: 'Attach your receipt'),
              const SizedBox(height: kSpace),
              Text(
                'Add a screenshot of the receipt from your wallet so '
                '${widget.payerName} can check it against their account.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpace * 1.5),
              Align(
                alignment: Alignment.centerLeft,
                child: _proof == null
                    ? OutlinedButton.icon(
                        onPressed: _attachProof,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Attach screenshot'),
                      )
                    : Semantics(
                        label: 'Payment screenshot attached',
                        child: PendingImageThumb(
                          bytes: _proof!.bytes,
                          onRemove: () => setState(() => _proof = null),
                          size: 160,
                        ),
                      ),
              ),

              if (shown == null && methods.hasValue) ...[
                const SizedBox(height: kSpace * 2),
                Text('How did you pay?', style: theme.textTheme.titleSmall),
                const SizedBox(height: kSpace),
                Wrap(
                  spacing: kSpace,
                  runSpacing: kSpace / 2,
                  children: [
                    for (final type in PaymentMethodType.values)
                      ChoiceChip(
                        // Cash has its own option above (D-70).
                        label: Text(type.label),
                        selected: _manualMethod == type,
                        onSelected: (_) => setState(() => _manualMethod = type),
                      ),
                  ],
                ),
              ],
            ],

            if (!_cash) ...[
              const SizedBox(height: kSpace * 2),
              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference number',
                  helperText: 'Optional, but it helps them find your payment',
                ),
              ),
            ],

            if (error != null) ...[
              const SizedBox(height: kSpace * 2),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],

            const SizedBox(height: kSpace * 3),
            FilledButton(
              // Disabled until there is proof (and while sending) — except
              // for cash, which has none.
              onPressed: (!_cash && _proof == null) || isSubmitting
                  ? null
                  : () => _submit(shown),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_cash ? 'I paid in cash' : "I've paid"),
            ),
            if (!_cash && _proof == null) ...[
              const SizedBox(height: kSpace),
              Text(
                "Attach a screenshot of your receipt to continue.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: kSpace * 2),
            Text(
              'Hati never moves money. Pay outside the app, then mark it '
              'here for ${widget.payerName} to confirm.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace * 2),
          ],
        ),
      ),
    );
  }

  /// The payer's default wallet, read in build (D-66).
  String? _preferred;

  /// The wallet to use: the one the bills ask for — if they all ask for the
  /// same one — else the payer's default. Null when any will do.
  PaymentMethod? _pinned(List<PaymentMethod> methods) {
    final billPins = widget.items.map((i) => i.bill.receiveMethodId).toSet();
    final id = (billPins.length == 1 ? billPins.first : null) ?? _preferred;
    if (id == null) return null;
    for (final method in methods) {
      if (method.id == id) return method;
    }
    return null;
  }

  /// The wallet card to show: the pinned one, else the debtor's pick, else the
  /// payer's default — preferring one with a QR when nothing else decides.
  PaymentMethod? _shownMethod(List<PaymentMethod> methods) {
    if (methods.isEmpty) return null;

    final pinned = _pinned(methods);
    if (pinned != null) return pinned;

    for (final method in methods) {
      if (method.id == _selectedMethodId) return method;
    }
    return methods.firstWhere(
      (m) => m.isDefault,
      orElse: () =>
          methods.firstWhere((m) => m.hasQr, orElse: () => methods.first),
    );
  }

  Future<void> _attachProof() async {
    final source = await askImageSource(context);
    if (source == null || !mounted) return;

    final picked = await ref.read(imageServiceProvider).pick(source);
    if (picked == null || !mounted) return;

    setState(() {
      _proof = picked;
      _error = null;
    });
  }

  Future<void> _submit(PaymentMethod? shown) async {
    final proof = _cash ? null : _proof;
    if (!_cash && proof == null) return;

    final actions = ref.read(settlementActionsProvider.notifier);
    final reference = _cash ? '' : _referenceController.text.trim();
    final method = _cash ? 'cash' : shown?.kind.wire ?? _manualMethod?.wire;
    final items = widget.items;
    final ok = items.length == 1
        ? await actions.markPaid(
            billShareId: items.single.share.id,
            billId: items.single.bill.id,
            groupId: items.single.bill.groupId,
            method: method,
            referenceNo: reference.isEmpty ? null : reference,
            proof: proof,
          )
        : await actions.markPaidBatch(
            billShareIds: [for (final i in items) i.share.id],
            billIds: [for (final i in items) i.bill.id],
            groupId: items.first.bill.groupId,
            method: method,
            referenceNo: reference.isEmpty ? null : reference,
            proof: proof,
          );

    if (!mounted) return;
    if (!ok) {
      setState(() => _error = actions.lastError);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.items.length == 1
              ? 'Marked as paid — ${widget.payerName} will confirm.'
              : 'Marked ${widget.items.length} bills as paid — '
                    '${widget.payerName} will confirm.',
        ),
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(kRadiusSm),
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
        ),
      ],
    );
  }
}

/// The payer's wallets: just the one they asked for, or a picker over all of
/// them when any will do.
class _HowToPay extends StatelessWidget {
  const _HowToPay({
    required this.methods,
    required this.shown,
    required this.pinned,
    required this.payerName,
    required this.onSelect,
  });

  final List<PaymentMethod> methods;
  final PaymentMethod shown;
  final bool pinned;
  final String payerName;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          pinned
              ? '$payerName asked to be paid through ${shown.displayLabel}.'
              : methods.length == 1
              ? 'Send it to ${shown.displayLabel}.'
              : 'Pay through any of $payerName\'s wallets.',
          style: theme.textTheme.bodyMedium,
        ),
        if (!pinned && methods.length > 1) ...[
          const SizedBox(height: kSpace),
          Wrap(
            spacing: kSpace,
            runSpacing: kSpace / 2,
            children: [
              for (final method in methods)
                ChoiceChip(
                  avatar: method.hasQr
                      ? const Icon(Icons.qr_code_2, size: 18)
                      : null,
                  label: Text(method.displayLabel),
                  selected: method.id == shown.id,
                  onSelected: (_) => onSelect(method.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: kSpace * 1.5),
        _MethodCard(method: shown),
      ],
    );
  }
}

class _MethodCard extends ConsumerWidget {
  const _MethodCard({required this.method});

  final PaymentMethod method;

  /// Download the QR and put it in the gallery, ready to open from inside
  /// the wallet app (D-68).
  Future<void> _saveQr(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(attachmentStorageProvider)
          .download(bucket: StorageBucket.paymentQr, path: method.qrImagePath!);
      await ref
          .read(imageGalleryProvider)
          .save(
            bytes,
            name: 'Hati ${method.displayLabel} QR ${method.accountName}',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'QR saved to your gallery. In ${WalletLauncher.appName(method.kind)}, '
            'scan it from your photos.',
          ),
        ),
      );
    } on AttachmentFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not get the QR: ${failure.message}')),
      );
    } on GalleryFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(kSpace * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    method.displayLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (method.isDefault) ...[
                  const SizedBox(width: kSpace),
                  const Tag('Default'),
                ],
              ],
            ),
            const SizedBox(height: kSpace / 2),
            Text(method.accountName, style: theme.textTheme.bodySmall),
            if (method.hasQr) ...[
              const SizedBox(height: kSpace * 1.5),
              // Big enough to scan from another phone; tap to enlarge.
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusMd),
                  child: AttachmentImage(
                    key: ValueKey(method.qrImagePath),
                    bucket: StorageBucket.paymentQr,
                    path: method.qrImagePath!,
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                    semanticLabel: '${method.displayLabel} QR code',
                  ),
                ),
              ),
              const SizedBox(height: kSpace / 2),
              Center(
                child: TextButton.icon(
                  onPressed: () => _saveQr(context, ref),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Save QR'),
                ),
              ),
              Center(
                child: Text(
                  'Scan with ${method.kind.isEWallet ? method.kind.label : 'your banking app'}, '
                  'or tap to enlarge',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: kSpace),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    method.accountNumber,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy account number',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: method.accountNumber),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Copied')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (WalletLauncher.canOpen(method.kind)) ...[
              const SizedBox(height: kSpace),
              FilledButton.tonalIcon(
                onPressed: () => WalletLauncher.open(
                  method.kind,
                  isAndroid: !kIsWeb && Platform.isAndroid,
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text('Open ${WalletLauncher.appName(method.kind)}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoMethods extends StatelessWidget {
  const _NoMethods({required this.payerName});

  final String payerName;

  @override
  Widget build(BuildContext context) {
    return InfoNote(
      message:
          "$payerName hasn't added payment details yet. Ask them how "
          'they want to be paid — you can still mark it paid here.',
    );
  }
}
