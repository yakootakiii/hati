import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/profile/domain/payment_method.dart';
import 'package:hati/features/settlements/presentation/widgets/wallet_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const wallets = MethodChannel('hati/wallets');
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  late List<MethodCall> walletCalls;
  late List<MethodCall> launcherCalls;

  void stub({required bool installed}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(wallets, (call) async {
      walletCalls.add(call);
      return installed;
    });
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launcherCalls.add(call);
      return true;
    });
  }

  setUp(() {
    walletCalls = [];
    launcherCalls = [];
  });

  group('WalletLauncher (DECISIONS D-62)', () {
    test('opens an installed wallet by package, not the store', () async {
      stub(installed: true);

      final opened = await WalletLauncher.open(
        PaymentMethodType.gcash,
        isAndroid: true,
      );

      expect(opened, isTrue);
      expect(walletCalls.single.method, 'open');
      expect(walletCalls.single.arguments, {
        'package': 'com.globe.gcash.android',
      });
      expect(launcherCalls, isEmpty, reason: 'no Play Store when installed');
    });

    test(
      'falls back to the Play Store only when it is not installed',
      () async {
        stub(installed: false);

        final opened = await WalletLauncher.open(
          PaymentMethodType.maya,
          isAndroid: true,
        );

        expect(opened, isFalse);
        expect(walletCalls.single.arguments, {'package': 'com.paymaya'});
        expect(
          (launcherCalls.single.arguments as Map<Object?, Object?>)['url'],
          'https://play.google.com/store/apps/details?id=com.paymaya',
        );
      },
    );

    test('every wallet with an Open button has a package', () {
      for (final type in PaymentMethodType.values) {
        if (type == PaymentMethodType.bank || type == PaymentMethodType.other) {
          expect(WalletLauncher.canOpen(type), isFalse, reason: type.name);
        } else {
          expect(WalletLauncher.canOpen(type), isTrue, reason: type.name);
        }
      }
    });

    test('MariBank opens its app, still published as SeaBank', () {
      expect(
        WalletLauncher.androidPackages[PaymentMethodType.maribank],
        'ph.seabank.seabank',
      );
    });

    test('ShopeePay is opened through the Shopee app', () {
      expect(WalletLauncher.appName(PaymentMethodType.shopeepay), 'Shopee');
      expect(WalletLauncher.appName(PaymentMethodType.gcash), 'GCash');
    });
  });

  group('MariBank as a payment method', () {
    test('is a bank, paid to an account number', () {
      expect(
        PaymentMethodType.fromWire('maribank'),
        PaymentMethodType.maribank,
      );
      expect(PaymentMethodType.maribank.label, 'MariBank');
      expect(PaymentMethodType.maribank.isEWallet, isFalse);
    });
  });
}
