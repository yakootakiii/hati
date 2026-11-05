import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// The one-action empty state every list gets (spec §10.1).
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Only for actions that create something ("Add bill"); a plain
  /// navigation action gets no icon.
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: kPagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A quiet tile, not a hero illustration: the page should still
            // read as the app, just with nothing in it yet.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(kRadiusLg),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                icon,
                size: 26,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace * 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: kSpace * 0.75),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: kSpace * 3),
              if (actionIcon != null)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel!),
                )
              else
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline retry for a failed load — never a dialog (spec §10.1).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: kPagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: kSpace * 1.5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: kSpace * 2),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
