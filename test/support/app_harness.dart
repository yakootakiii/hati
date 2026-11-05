import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hati/app/app.dart';
import 'package:hati/app/router.dart';
import 'package:hati/core/supabase/supabase_providers.dart';
import 'package:hati/features/auth/data/auth_repository.dart';
import 'package:hati/features/auth/domain/auth_snapshot.dart';
import 'package:hati/core/images/attachment_storage.dart';
import 'package:hati/core/images/image_service.dart';
import 'package:hati/core/supabase/realtime_service.dart';
import 'package:hati/features/activity/data/activity_repository.dart';
import 'package:hati/features/notifications/data/notifications_repository.dart';
import 'package:hati/features/recurring/data/recurring_repository.dart';
import 'package:hati/features/bills/data/bills_repository.dart';
import 'package:hati/features/groups/data/groups_repository.dart';
import 'package:hati/core/images/image_gallery.dart';
import 'package:hati/core/links/invite_links.dart';
import 'package:hati/core/push/push_registration.dart';
import 'package:hati/features/profile/data/account_repository.dart';
import 'package:hati/features/profile/data/payment_methods_repository.dart';
import 'package:hati/features/settlements/data/payments_repository.dart';

import 'fake_auth_repository.dart';
import 'fake_bills_repository.dart';
import 'fake_groups_repository.dart';
import 'fake_account_repository.dart';
import 'fake_activity_repository.dart';
import 'fake_links.dart';
import 'fake_push.dart';
import 'fake_image_services.dart';
import 'fake_notifications_repository.dart';
import 'fake_recurring_repository.dart';
import 'fake_realtime_service.dart';
import 'fake_payment_methods_repository.dart';
import 'fake_payments_repository.dart';

/// A booted app wired to fakes, with the handles a test needs to drive it.
class Harness {
  Harness({
    required this.tester,
    required this.auth,
    required this.groups,
    required this.bills,
    required this.payments,
    required this.paymentMethods,
    required this.images,
    required this.storage,
    required this.activity,
    required this.realtime,
    required this.notifications,
    required this.recurring,
    required this.container,
  });

  final WidgetTester tester;
  final FakeAuthRepository auth;
  final FakeGroupsRepository groups;
  final FakeBillsRepository bills;
  final FakePaymentsRepository payments;
  final FakePaymentMethodsRepository paymentMethods;
  final FakeImageService images;
  final FakeAttachmentStorage storage;
  final FakeActivityRepository activity;
  final FakeRealtimeService realtime;
  final FakeNotificationsRepository notifications;
  final FakeRecurringRepository recurring;
  final ProviderContainer container;

  GoRouter get router => container.read(routerProvider);

  /// Where the router currently is, for asserting on redirects.
  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Future<void> go(String location) async {
    router.go(location);
    await tester.pumpAndSettle();
  }
}

/// Boots [HatiApp] against in-memory repositories.
Future<Harness> pumpApp(
  WidgetTester tester, {
  AuthSnapshot? session,
  bool configured = true,
  FakeGroupsRepository? groups,
  FakeBillsRepository? bills,
  FakePaymentsRepository? payments,
  FakePaymentMethodsRepository? paymentMethods,
  FakeImageService? images,
  FakeAttachmentStorage? storage,
  FakeActivityRepository? activity,
  FakeRealtimeService? realtime,
  FakeNotificationsRepository? notifications,
  FakeRecurringRepository? recurring,
  FakeAccountRepository? account,
  FakePushMessaging? push,
  FakeImageGallery? gallery,
  FakeLinkSource? links,
  FakeDeviceTokenRepository? deviceTokens,

  /// 2.0 exercises the 200% text scale the spec asks to support (§11).
  double textScale = 1.0,
  Brightness platformBrightness = Brightness.light,
  Size surfaceSize = const Size(400, 900),
}) async {
  // Mirrors main(): en_PH date symbols must be loaded before any DateFormat.
  await initializeDateFormatting('en_PH');

  // A phone-shaped surface: the 800x600 default is neither a phone nor a
  // tablet, and at 200% text it overflows things that are fine in practice.
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    ..platformBrightnessTestValue = platformBrightness;
  addTearDown(() {
    tester.platformDispatcher
      ..clearTextScaleFactorTestValue()
      ..clearPlatformBrightnessTestValue();
  });

  final auth = FakeAuthRepository(initial: session);
  addTearDown(auth.dispose);

  final groupsRepository = groups ?? FakeGroupsRepository();
  final billsRepo = bills ?? FakeBillsRepository();
  final paymentsRepo = payments ?? FakePaymentsRepository();
  final methodsRepo = paymentMethods ?? FakePaymentMethodsRepository();
  final imageService = images ?? FakeImageService();
  final attachmentStorage = storage ?? FakeAttachmentStorage();
  final activityRepo = activity ?? FakeActivityRepository();
  final realtimeService = realtime ?? FakeRealtimeService();
  final notificationsRepo = notifications ?? FakeNotificationsRepository();
  final recurringRepo = recurring ?? FakeRecurringRepository();
  final accountRepo = (account ?? FakeAccountRepository())..auth = auth;
  // Push is off unless a test asks for it, so no other test has to care.
  final pushMessaging = push ?? FakePushMessaging(available: false);
  final deviceTokenRepo = deviceTokens ?? FakeDeviceTokenRepository();
  final imageGalleryFake = gallery ?? FakeImageGallery();
  final linkSource = links ?? FakeLinkSource();

  final container = ProviderContainer(
    overrides: [
      isBackendConfiguredProvider.overrideWithValue(configured),
      authRepositoryProvider.overrideWithValue(auth),
      groupsRepositoryProvider.overrideWithValue(groupsRepository),
      billsRepositoryProvider.overrideWithValue(billsRepo),
      paymentsRepositoryProvider.overrideWithValue(paymentsRepo),
      paymentMethodsRepositoryProvider.overrideWithValue(methodsRepo),
      imageServiceProvider.overrideWithValue(imageService),
      attachmentStorageProvider.overrideWithValue(attachmentStorage),
      activityRepositoryProvider.overrideWithValue(activityRepo),
      realtimeServiceProvider.overrideWithValue(realtimeService),
      notificationsRepositoryProvider.overrideWithValue(notificationsRepo),
      recurringRepositoryProvider.overrideWithValue(recurringRepo),
      accountRepositoryProvider.overrideWithValue(accountRepo),
      pushMessagingProvider.overrideWithValue(pushMessaging),
      deviceTokenRepositoryProvider.overrideWithValue(deviceTokenRepo),
      imageGalleryProvider.overrideWithValue(imageGalleryFake),
      linkSourceProvider.overrideWithValue(linkSource),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const HatiApp()),
  );
  await tester.pumpAndSettle();

  return Harness(
    tester: tester,
    auth: auth,
    groups: groupsRepository,
    bills: billsRepo,
    payments: paymentsRepo,
    paymentMethods: methodsRepo,
    images: imageService,
    storage: attachmentStorage,
    activity: activityRepo,
    realtime: realtimeService,
    notifications: notificationsRepo,
    recurring: recurringRepo,
    container: container,
  );
}

/// A signed-in session, for the many tests that only care about what is past
/// the auth gate.
const signedIn = AuthSnapshot(userId: 'bea', emailConfirmed: true);

/// A signed-in session for a named user.
AuthSnapshot signedInAs(String userId) =>
    AuthSnapshot(userId: userId, emailConfirmed: true);

/// Silences overflow errors from the fixed 800x600 test surface, which are a
/// property of the harness rather than the layout.
void ignoreOverflowErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception is FlutterError &&
        details.exception.toString().contains('overflowed')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// Collects layout overflow errors raised while [body] runs.
///
/// Flutter reports an overflow as a FlutterError rather than an exception, so
/// a test that only checks for thrown exceptions will happily pass over a
/// visibly broken screen.
Future<List<String>> collectOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;

  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first);
    } else {
      original?.call(details);
    }
  };

  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return overflows;
}
