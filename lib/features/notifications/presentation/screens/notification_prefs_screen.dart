import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../domain/notification_models.dart';
import '../notifications_controller.dart';

/// Notification preferences (spec §10).
///
/// Each switch covers one or more event types; the mapping lives in the
/// fan-out trigger (DECISIONS D-44), which is what actually honours it — an
/// unwanted notification is never written rather than written and hidden.
class NotificationPrefsScreen extends ConsumerWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load your preferences.',
          onRetry: () => ref.invalidate(notificationPrefsProvider),
        ),
        data: (current) => ListView(
          children: [
            _Switch(
              title: 'New and changed bills',
              subtitle: 'When someone adds, edits or voids a bill you are on',
              value: current.newBill,
              onChanged: (value) =>
                  _save(ref, current.copyWith(newBill: value)),
            ),
            _Switch(
              title: 'Someone says they paid',
              subtitle: 'When a payment needs your confirmation',
              value: current.paymentMarked,
              onChanged: (value) =>
                  _save(ref, current.copyWith(paymentMarked: value)),
            ),
            _Switch(
              title: 'Your payment was decided',
              subtitle: 'When a payment of yours is confirmed or rejected',
              value: current.paymentConfirmed,
              onChanged: (value) =>
                  _save(ref, current.copyWith(paymentConfirmed: value)),
            ),
            _Switch(
              title: 'Comments',
              subtitle: 'When someone comments on a bill you are on',
              value: current.comments,
              onChanged: (value) =>
                  _save(ref, current.copyWith(comments: value)),
            ),
            _Switch(
              title: 'Reminders and nudges',
              subtitle: 'When something has been unpaid for a while',
              value: current.reminders,
              onChanged: (value) =>
                  _save(ref, current.copyWith(reminders: value)),
            ),
          ],
        ),
      ),
    );
  }

  void _save(WidgetRef ref, NotificationPrefs prefs) =>
      ref.read(notificationActionsProvider.notifier).savePrefs(prefs);
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
