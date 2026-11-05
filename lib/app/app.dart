import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/links/invite_links.dart';
import '../core/push/push_registration.dart';
import '../core/settings/app_settings.dart';
import '../core/supabase/supabase_providers.dart';
import '../core/widgets/config_missing_screen.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class HatiApp extends ConsumerWidget {
  const HatiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A fixed palette rather than wallpaper colours, so the brand reads the
    // same on every phone (DECISIONS D-59).
    final light = AppTheme.build(brightness: Brightness.light);
    final dark = AppTheme.build(brightness: Brightness.dark);

    if (!ref.watch(isBackendConfiguredProvider)) {
      return MaterialApp(
        title: 'Hati',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        home: const ConfigMissingScreen(),
      );
    }

    // Kept alive for the whole session: registers the phone for push and
    // routes notification taps (D-65).
    ref.watch(pushRegistrationProvider);
    // Opens invite links in the join screen (D-69).
    ref.watch(inviteLinkRouterProvider);

    return MaterialApp.router(
      title: 'Hati',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: light,
      darkTheme: dark,
      // Follows the system by default; overridable in settings (spec §11).
      themeMode: ref.watch(appThemeModeProvider),
    );
  }
}
