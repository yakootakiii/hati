import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Shown when the build has no Supabase project attached.
///
/// Every screen past sign-in needs a backend, so rather than crash on a missing
/// key at startup, the app boots and says what is missing.
class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: kPagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: kSpace * 2),
                  Text('No Supabase project', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: kSpace),
                  Text(
                    'This build was compiled without SUPABASE_URL and '
                    'SUPABASE_ANON_KEY, so there is nothing to sign in to.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: kSpace * 3),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(kSpace * 1.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(kRadiusMd),
                    ),
                    child: Text(
                      'cp .env.example .env\n'
                      '# fill in both values, then:\n'
                      'flutter run --dart-define-from-file=.env',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
