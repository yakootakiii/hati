import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/theme/app_theme.dart';
import 'push_registration.dart';

part 'push_prompt.g.dart';

/// "Not now", for the rest of this visit.
@Riverpod(keepAlive: true)
class PushPromptDismissed extends _$PushPromptDismissed {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

/// Web only (D-72): browsers let a page ask for notifications from a tap,
/// and iPhones only after "Add to Home Screen" — so the web app says so,
/// instead of asking on its own the way the Android app does.
class PushPrompt extends ConsumerWidget {
  const PushPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsTap = ref.watch(pushMessagingProvider).needsUserGesture;
    final status = ref.watch(pushRegistrationProvider);
    final dismissed = ref.watch(pushPromptDismissedProvider);

    if (!needsTap || dismissed) return const SizedBox.shrink();
    if (status != PushStatus.askable &&
        status != PushStatus.needsHomeScreen) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final homeScreen = status == PushStatus.needsHomeScreen;

    return Padding(
      padding: const EdgeInsets.only(top: kSpace),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get notified when someone pays you',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        homeScreen
                            ? 'On iPhone, notifications need Hati on your Home '
                                'Screen: tap Share, then "Add to Home Screen", '
                                'and open Hati from there.'
                            : 'Payments to confirm, new bills and reminders — '
                                'even when Hati is closed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(pushPromptDismissedProvider.notifier).dismiss(),
                  child: const Text('Not now'),
                ),
                if (!homeScreen)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      visualDensity: VisualDensity.compact,
                    ),
                    // Straight from the tap: Safari ignores a delayed ask.
                    onPressed: () =>
                        ref.read(pushRegistrationProvider.notifier).enable(),
                    child: const Text('Turn on'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
