import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../../core/widgets/surfaces.dart';

/// Appearance (spec §11: follow the system by default, override here).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appThemeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      // RadioGroup rather than per-tile groupValue/onChanged, both of which
      // are deprecated as of Flutter 3.32.
      body: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (value) {
          if (value != null) {
            ref.read(appThemeModeProvider.notifier).set(value);
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ContentWidth(
              child: ListGroup(
                dividerIndent: 56,
                children: [
                  for (final (mode, title, subtitle) in const [
                    (
                      ThemeMode.system,
                      'Match my phone',
                      'Follows your device setting',
                    ),
                    (ThemeMode.light, 'Light', 'Always light'),
                    (ThemeMode.dark, 'Dark', 'Always dark'),
                  ])
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(title),
                      subtitle: Text(subtitle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
