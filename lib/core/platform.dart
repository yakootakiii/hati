import 'package:flutter/foundation.dart';

/// Which kind of Hati this is (DECISIONS D-71). Browser-safe: `dart:io`'s
/// `Platform` throws on the web, so the app asks Flutter instead.
abstract final class AppPlatform {
  static bool get isWeb => kIsWeb;

  /// The installed Android app — not Chrome on an Android phone.
  static bool get isAndroidApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOSApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The browser is on an iPhone or iPad — for choosing wallet links.
  static bool get isIOSDevice => defaultTargetPlatform == TargetPlatform.iOS;
}
