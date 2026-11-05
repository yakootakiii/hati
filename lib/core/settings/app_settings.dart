import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_settings.g.dart';

/// Settings that belong to this device rather than the account.
///
/// Theme is the only one so far. It is deliberately local: which appearance
/// someone wants on their phone is not something to sync to a server, and
/// storing it locally means it applies before the first frame rather than
/// after a round trip.
abstract interface class SettingsStore {
  Future<ThemeMode> themeMode();

  Future<void> setThemeMode(ThemeMode mode);
}

class PreferencesSettingsStore implements SettingsStore {
  static const _themeKey = 'theme_mode';

  @override
  Future<ThemeMode> themeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // Anything else, including nothing stored, follows the system — which is
      // the documented default (spec §11).
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}

/// A store that forgets, for builds with no platform channel available.
class InMemorySettingsStore implements SettingsStore {
  ThemeMode _mode = ThemeMode.system;

  @override
  Future<ThemeMode> themeMode() async => _mode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => _mode = mode;
}

@Riverpod(keepAlive: true)
SettingsStore settingsStore(Ref ref) => PreferencesSettingsStore();

/// The chosen appearance.
///
/// Starts on [ThemeMode.system] and settles on the stored value once it loads,
/// so the first frame is never blocked on disk.
@Riverpod(keepAlive: true)
class AppThemeMode extends _$AppThemeMode {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final stored = await ref.read(settingsStoreProvider).themeMode();
    if (stored != state) state = stored;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsStoreProvider).setThemeMode(mode);
  }
}
