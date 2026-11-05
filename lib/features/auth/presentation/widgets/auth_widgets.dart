import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Shared layout for the auth screens: centred, scrollable so it survives 200%
/// text scale, and capped in width so it doesn't sprawl on a tablet.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.showBackButton = true,
    this.footer,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBackButton;

  /// Pinned below the scrolling content — the Terms notice, on the screens
  /// that create or open an account.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: showBackButton),
      bottomNavigationBar: footer == null
          ? null
          : SafeArea(top: false, child: footer!),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: kPagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: kSpace),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: kSpace * 4),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error, per spec §10.1: errors belong on the page with a retry, not
/// in a dialog.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace * 2),
      child: Container(
        padding: const EdgeInsets.all(kSpace * 1.5),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: kSpace * 1.5),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A primary action that shows progress in place, so the button never moves or
/// changes size mid-tap.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    required this.label,
    required this.onPressed,
    required this.isBusy,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isBusy ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: isBusy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
