import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../profile/domain/payment_method.dart';

/// "Open GCash", "Open Maya" and the rest (spec §9, DECISIONS D-62).
///
/// On Android the wallet is launched by its package name through a small
/// native channel (MainActivity.kt) — the same as tapping its icon, so it
/// opens the app itself rather than the Play Store. The store is only the
/// fallback when the app really is not installed.
///
/// On iOS apps can only be reached by URL scheme. The schemes below are the
/// ones the Android apps register; the iOS apps are believed to match but
/// that is unverified, so iOS falls back to the App Store.
///
/// No wallet offers a public way to prefill an amount, so this only opens the
/// app; the debtor still enters the amount or scans the QR.
abstract final class WalletLauncher {
  static const MethodChannel _channel = MethodChannel('hati/wallets');

  /// Package names, checked on a real phone and against the Play Store
  /// (November 2026). ShopeePay lives inside the Shopee app, and MariBank is
  /// still published under its old SeaBank package.
  @visibleForTesting
  static const Map<PaymentMethodType, String> androidPackages = {
    PaymentMethodType.gcash: 'com.globe.gcash.android',
    PaymentMethodType.maya: 'com.paymaya',
    PaymentMethodType.gotyme: 'ph.com.gotyme',
    PaymentMethodType.shopeepay: 'com.shopee.ph',
    PaymentMethodType.grabpay: 'com.grabtaxi.passenger',
    PaymentMethodType.coinsph: 'asia.coins.mobile',
    PaymentMethodType.palawanpay: 'com.palawanpay.ewallet',
    PaymentMethodType.maribank: 'ph.seabank.seabank',
  };

  /// iOS schemes, from what the Android apps register (see above).
  static const Map<PaymentMethodType, String> _iosSchemes = {
    PaymentMethodType.gcash: 'gcash://',
    PaymentMethodType.maya: 'paymaya://',
    PaymentMethodType.gotyme: 'gotyme://',
    PaymentMethodType.maribank: 'seabankph://',
  };

  /// App Store pages, where known. The rest fall back to an App Store search.
  static const Map<PaymentMethodType, String> _iosStore = {
    PaymentMethodType.gcash: 'https://apps.apple.com/ph/app/gcash/id520020791',
    PaymentMethodType.maya: 'https://apps.apple.com/ph/app/id991673672',
  };

  /// The name on the button: ShopeePay opens inside the Shopee app.
  static String appName(PaymentMethodType type) =>
      type == PaymentMethodType.shopeepay ? 'Shopee' : type.label;

  /// True when this method maps to an app worth offering to open.
  static bool canOpen(PaymentMethodType type) =>
      androidPackages.containsKey(type);

  /// Returns true if the wallet opened, false if the store was opened instead.
  static Future<bool> open(
    PaymentMethodType type, {
    required bool isAndroid,
  }) async {
    final package = androidPackages[type];
    if (package == null) return false;

    if (isAndroid) {
      try {
        final opened = await _channel.invokeMethod<bool>(
          'open',
          {'package': package},
        );
        if (opened ?? false) return true;
      } on PlatformException {
        // Falls through to the store.
      } on MissingPluginException {
        // Falls through to the store.
      }
      await _launch(
        Uri.parse('https://play.google.com/store/apps/details?id=$package'),
      );
      return false;
    }

    final scheme = _iosSchemes[type];
    if (scheme != null) {
      try {
        if (await _launch(Uri.parse(scheme))) return true;
      } on Exception {
        // Falls through to the store.
      }
    }
    await _launch(
      Uri.parse(
        _iosStore[type] ??
            'https://apps.apple.com/ph/search?term='
                '${Uri.encodeComponent(appName(type))}',
      ),
    );
    return false;
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
