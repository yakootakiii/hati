import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../groups/presentation/widgets/direct_invite_widgets.dart';
import '../../domain/notification_models.dart';
import '../notifications_controller.dart';

/// The notifications list (spec §10). Tapping one deep-links through
/// `data.route`.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationListProvider);
    final hasUnread =
        (ref.watch(unreadNotificationCountProvider).asData?.value ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // An icon rather than a text button: at 200% text scale the label
          // and the settings icon no longer fit the app bar together.
          if (hasUnread)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: () =>
                  ref.read(notificationActionsProvider.notifier).markAllRead(),
              icon: const Icon(Icons.done_all),
            ),
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () => context.push(Routes.notificationPrefs),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: 'Could not load your notifications.',
          onRetry: () => ref.invalidate(notificationListProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'Nothing to catch up on',
              message:
                  "We'll tell you when a bill, payment or comment needs you.",
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationListProvider);
              await ref.read(notificationListProvider.future);
            },
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) =>
                  _NotificationRow(notification: list[index]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invite = notification.groupInvite;

    final tile = ListTile(
      leading: Icon(
        _icon,
        color: notification.isUnread
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      // Unread is carried by weight and a labelled dot, never colour alone
      // (spec §11).
      title: Text(
        notification.title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: notification.isUnread
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '${invite?.outcome ?? notification.body}\n'
        '${DateFormat.MMMd('en_PH').add_jm().format(notification.createdAt.toLocal())}',
      ),
      isThreeLine: true,
      trailing: notification.isUnread
          ? Semantics(
              label: 'Unread',
              child: Icon(
                Icons.circle,
                size: 10,
                color: theme.colorScheme.primary,
              ),
            )
          : null,
      onTap: () => _open(context, ref),
    );

    if (invite == null || !invite.isPending) return tile;

    return Column(
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, kSpace * 2),
          child: InviteResponseButtons(
            inviteId: invite.inviteId,
            groupName: invite.groupName,
          ),
        ),
      ],
    );
  }

  IconData get _icon => switch (notification.type) {
    'bill_created' || 'recurring_generated' => Icons.receipt_long_outlined,
    'bill_edited' => Icons.edit_outlined,
    'bill_voided' => Icons.block,
    'payment_marked' => Icons.payments_outlined,
    'payment_confirmed' => Icons.check_circle_outline,
    'payment_rejected' => Icons.error_outline,
    'comment_added' => Icons.chat_bubble_outline,
    'member_joined' => Icons.person_add_alt,
    'group_invite' => Icons.group_add_outlined,
    'reminder' || 'nudge' => Icons.alarm,
    _ => Icons.notifications_outlined,
  };

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // Captured before the await: marking read invalidates the list that built
    // this row.
    final actions = ref.read(notificationActionsProvider.notifier);
    final router = GoRouter.of(context);

    if (notification.isUnread) {
      await actions.markRead(notification.id);
    }

    // An accepted invite opens the group; a pending one is answered with the
    // buttons, not by tapping the row.
    final invite = notification.groupInvite;
    final route = invite != null
        ? (invite.isAccepted ? Routes.groupDetail(invite.groupId) : null)
        : notification.route;
    if (route != null) unawaited(router.push(route));
  }
}
