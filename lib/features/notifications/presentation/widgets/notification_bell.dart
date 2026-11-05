import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../notifications_controller.dart';

/// The bell in the app bar, with an unread badge (spec §10).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;

    return IconButton(
      // The count is in the tooltip as well as the badge, so it is not
      // carried by a visual cue alone (spec §11).
      tooltip: count == 0
          ? 'Notifications'
          : '$count unread ${count == 1 ? 'notification' : 'notifications'}',
      onPressed: () => context.push(Routes.notifications),
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
