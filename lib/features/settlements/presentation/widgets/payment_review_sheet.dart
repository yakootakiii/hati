import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/semantic_colors.dart';
import '../../../../core/images/image_models.dart';
import '../../../../core/widgets/amount_field.dart';
import '../../../../core/widgets/image_widgets.dart';
import '../../../../core/widgets/surfaces.dart';
import '../../../../core/money/money.dart';
import '../../domain/payment.dart';
import '../settlements_controller.dart';

/// Payment review (spec §10): the payer sees the claim and decides.
class PaymentReviewSheet extends ConsumerStatefulWidget {
  const PaymentReviewSheet({
    required this.payment,
    required this.billId,
    required this.groupId,
    required this.debtorName,
    super.key,
  });

  final Payment payment;
  final String billId;
  final String groupId;
  final String debtorName;

  static Future<void> show(
    BuildContext context, {
    required Payment payment,
    required String billId,
    required String groupId,
    required String debtorName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaymentReviewSheet(
        payment: payment,
        billId: billId,
        groupId: groupId,
        debtorName: debtorName,
      ),
    );
  }

  @override
  ConsumerState<PaymentReviewSheet> createState() =>
      _PaymentReviewSheetState();
}

class _PaymentReviewSheetState extends ConsumerState<PaymentReviewSheet> {
  final _reasonController = TextEditingController();
  bool _rejecting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionState = ref.watch(settlementActionsProvider);
    final error = _error;
    final payment = widget.payment;

    // Part of one payment for several bills (D-67): show and decide the
    // whole of it, since that is what arrived in the payer's wallet.
    final batchId = payment.batchId;
    final batch = batchId == null
        ? const <Payment>[]
        : (ref.watch(batchPaymentsProvider(batchId)).asData?.value ??
                const <Payment>[])
            .where((p) => p.isPending)
            .toList();
    final isBatch = batch.length > 1;
    final amount = isBatch
        ? Money(batch.fold(0, (t, p) => t + p.amount.centavos))
        : payment.amount;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.debtorName} says they paid',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: kSpace / 2),
              AmountText(
                amount,
                style: theme.textTheme.displaySmall,
                color: context.money.pending,
              ),
              if (isBatch) ...[
                const SizedBox(height: kSpace * 1.5),
                InfoNote(
                  icon: Icons.done_all,
                  message: 'One payment for ${batch.length} bills. '
                      'Confirming or rejecting it covers all of them.',
                ),
              ],

              const SizedBox(height: kSpace * 3),
              _DetailRow(label: 'Method', value: payment.methodLabel),
              if (payment.referenceNo != null)
                _DetailRow(label: 'Reference', value: payment.referenceNo!),
              if (payment.createdAt != null)
                _DetailRow(
                  label: 'Marked',
                  value: DateFormat.yMMMd('en_PH')
                      .add_jm()
                      .format(payment.createdAt!.toLocal()),
                ),
              if (payment.proofPath != null) ...[
                const SizedBox(height: kSpace * 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusMd),
                  child: AttachmentImage(
                    bucket: StorageBucket.paymentProofs,
                    path: payment.proofPath!,
                    height: 220,
                    fit: BoxFit.contain,
                    semanticLabel: 'Payment screenshot from ${widget.debtorName}',
                  ),
                ),
              ],

              if (error != null) ...[
                const SizedBox(height: kSpace * 2),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],

              const SizedBox(height: kSpace * 3),

              if (_rejecting) ...[
                TextField(
                  controller: _reasonController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: "What's wrong?",
                    helperText: "They'll see this, so be specific",
                  ),
                ),
                const SizedBox(height: kSpace * 2),
                FilledButton(
                  onPressed: actionState.isLoading ? null : _reject,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: const Text("I didn't get it"),
                ),
                TextButton(
                  onPressed: () => setState(() => _rejecting = false),
                  child: const Text('Back'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: actionState.isLoading ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: Text('Confirm ${amount.format()} received'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: kSpace),
                TextButton(
                  onPressed: () => setState(() => _rejecting = true),
                  child: const Text("I didn't get it"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final actions = ref.read(settlementActionsProvider.notifier);
    final batchId = widget.payment.batchId;
    final ok = batchId != null
        ? await actions.confirmBatch(
            batchId: batchId,
            billIds: [widget.billId],
            groupId: widget.groupId,
          )
        : await actions.confirm(
            paymentId: widget.payment.id,
            billId: widget.billId,
            groupId: widget.groupId,
          );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() =>
          _error = ref.read(settlementActionsProvider.notifier).lastError);
    }
  }

  Future<void> _reject() async {
    final actions = ref.read(settlementActionsProvider.notifier);
    final reason = _reasonController.text.trim().isEmpty
        ? null
        : _reasonController.text.trim();
    final batchId = widget.payment.batchId;
    final ok = batchId != null
        ? await actions.rejectBatch(
            batchId: batchId,
            billIds: [widget.billId],
            groupId: widget.groupId,
            reason: reason,
          )
        : await actions.reject(
            paymentId: widget.payment.id,
            billId: widget.billId,
            groupId: widget.groupId,
            reason: reason,
          );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() =>
          _error = ref.read(settlementActionsProvider.notifier).lastError);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
