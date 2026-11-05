import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/utils/stream_listenable.dart';
import '../core/widgets/surfaces.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/reset_password_screen.dart';
import '../features/auth/presentation/screens/sign_up_screen.dart';
import '../features/auth/presentation/screens/verify_email_screen.dart';
import '../features/auth/presentation/screens/welcome_screen.dart';
import '../features/legal/terms_screen.dart';
import '../features/groups/presentation/screens/create_group_screen.dart';
import '../features/groups/presentation/screens/group_detail_screen.dart';
import '../features/groups/presentation/screens/group_settings_screen.dart';
import '../features/groups/presentation/screens/groups_list_screen.dart';
import '../features/groups/presentation/screens/join_group_screen.dart';
import '../features/groups/presentation/screens/members_screen.dart';
import '../features/bills/presentation/screens/add_edit_bill_screen.dart';
import '../features/bills/presentation/screens/bill_detail_screen.dart';
import '../features/activity/presentation/screens/activity_screen.dart';
import '../features/bills/presentation/screens/home_screen.dart';
import '../features/notifications/presentation/screens/notification_prefs_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/recurring/presentation/screens/recurring_bills_screen.dart';
import '../features/recurring/presentation/screens/recurring_form_screen.dart';
import '../features/profile/presentation/screens/appearance_screen.dart';
import '../features/profile/presentation/screens/delete_account_screen.dart';
import '../features/profile/presentation/screens/payment_methods_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';

part 'router.g.dart';

/// Route paths, in one place so deep links and navigation calls can't drift.
abstract final class Routes {
  static const welcome = '/welcome';
  static const login = '/login';
  static const signUp = '/sign-up';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';

  /// Readable signed in or out (DECISIONS D-61, D-63).
  static const terms = '/terms';
  static const privacy = '/privacy';

  /// Signed in by a reset link, not yet given a new password.
  static const resetPassword = '/reset-password';

  static const home = '/';
  static const groups = '/groups';
  static const activity = '/activity';

  static const createGroup = '/groups/new';
  static const groupDetailPath = '/groups/:groupId';
  static const groupMembersPath = '/groups/:groupId/members';
  static const groupSettingsPath = '/groups/:groupId/settings';

  static const addBillPath = '/groups/:groupId/bills/new';
  static const editBillPath = '/groups/:groupId/bills/:billId/edit';
  static const billDetailPath = '/bills/:billId';
  static const profile = '/profile';
  static const paymentMethods = '/profile/payment-methods';
  static const appearance = '/profile/appearance';
  static const deleteAccount = '/profile/delete-account';
  static const recurringPath = '/groups/:groupId/recurring';
  static const addRecurringPath = '/groups/:groupId/recurring/new';
  static const editRecurringPath = '/groups/:groupId/recurring/:templateId';

  static String recurring(String groupId) => '/groups/$groupId/recurring';
  static String addRecurring(String groupId) =>
      '/groups/$groupId/recurring/new';
  static String editRecurring(String groupId, String templateId) =>
      '/groups/$groupId/recurring/$templateId';

  static const notifications = '/notifications';
  static const notificationPrefs = '/profile/notifications';

  static String groupDetail(String groupId) => '/groups/$groupId';
  static String groupMembers(String groupId) => '/groups/$groupId/members';
  static String groupSettings(String groupId) => '/groups/$groupId/settings';
  static String addBill(String groupId) => '/groups/$groupId/bills/new';
  static String editBill(String groupId, String billId) =>
      '/groups/$groupId/bills/$billId/edit';
  static String billDetail(String billId) => '/bills/$billId';

  /// Invite deep link (spec §8): `https://hati-a1a23.web.app/join/TOKEN`,
  /// routed here by InviteLinkRouter (DECISIONS D-69).
  static const join = '/join/:token';

  static String joinToken(String token) => '/join/$token';

  /// Reachable without a session.
  static const Set<String> public = {
    welcome,
    login,
    signUp,
    forgotPassword,
    verifyEmail,
  };
}

/// Holds an invite token captured before sign-in, so the join resumes
/// afterwards (spec §8.1).
@Riverpod(keepAlive: true)
class PendingInvite extends _$PendingInvite {
  @override
  String? build() => null;

  void stash(String token) => state = token;

  String? take() {
    final token = state;
    state = null;
    return token;
  }
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final repository = ref.watch(authRepositoryProvider);

  final refresh = StreamListenable(repository.changes);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = repository.snapshot.isSignedIn;
      final target = state.matchedLocation;

      if (!signedIn) {
        // The Terms must be readable before anyone agrees to them.
        if (target == Routes.terms || target == Routes.privacy) return null;

        // Hold on to the invite so the join can finish after sign-in.
        if (target.startsWith('/join/')) {
          final token = state.pathParameters['token'];
          if (token != null) {
            ref.read(pendingInviteProvider.notifier).stash(token);
          }
          return Routes.welcome;
        }
        return Routes.public.contains(target) ? null : Routes.welcome;
      }

      // A reset link signs the user in for one purpose. Hold them on the
      // reset screen until the new password is saved (DECISIONS D-60).
      if (repository.snapshot.recoveringPassword) {
        return target == Routes.resetPassword ? null : Routes.resetPassword;
      }
      if (target == Routes.resetPassword) return Routes.home;

      if (Routes.public.contains(target)) {
        final pending = ref.read(pendingInviteProvider.notifier).take();
        return pending == null ? Routes.home : Routes.joinToken(pending);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (_, _) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: Routes.terms,
        builder: (_, _) => const TermsScreen(),
      ),
      GoRoute(
        path: Routes.privacy,
        builder: (_, _) => const PrivacyScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: Routes.join,
        builder: (_, state) =>
            JoinGroupScreen(token: state.pathParameters['token']!),
      ),
      // Outside the shell, so the bottom bar is hidden while drilling in.
      GoRoute(
        path: Routes.createGroup,
        builder: (_, _) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: Routes.groupDetailPath,
        builder: (_, state) =>
            GroupDetailScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.groupMembersPath,
        builder: (_, state) =>
            MembersScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.addBillPath,
        builder: (_, state) =>
            AddEditBillScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.editBillPath,
        builder: (_, state) => AddEditBillScreen(
          groupId: state.pathParameters['groupId']!,
          billId: state.pathParameters['billId'],
        ),
      ),
      // Declared before the :templateId route so "new" is not read as an id.
      GoRoute(
        path: Routes.groupSettingsPath,
        builder: (_, state) =>
            GroupSettingsScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.addRecurringPath,
        builder: (_, state) =>
            RecurringFormScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.recurringPath,
        builder: (_, state) =>
            RecurringBillsScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: Routes.editRecurringPath,
        builder: (_, state) => RecurringFormScreen(
          groupId: state.pathParameters['groupId']!,
          templateId: state.pathParameters['templateId'],
        ),
      ),
      GoRoute(
        path: Routes.billDetailPath,
        // The bill card opens into its detail (spec §11).
        pageBuilder: (_, state) => fadeThroughPage(
          key: state.pageKey,
          child: BillDetailScreen(billId: state.pathParameters['billId']!),
        ),
      ),
      GoRoute(
        path: Routes.paymentMethods,
        builder: (_, _) => const PaymentMethodsScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.appearance,
        builder: (_, _) => const AppearanceScreen(),
      ),
      GoRoute(
        path: Routes.deleteAccount,
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: Routes.notificationPrefs,
        builder: (_, _) => const NotificationPrefsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.groups,
                builder: (_, _) => const GroupsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.activity,
                builder: (_, _) => const ActivityScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// M3's fade-through, used where the spec asks for a container transform
/// (§11).
///
/// A true container transform needs the `animations` package's OpenContainer,
/// which drives its own navigation and does not compose with go_router's
/// declarative routing. Fade-through is M3's own answer for a transition
/// between screens that are not parent and child, and it reads as the same
/// family of motion (DECISIONS D-52).
CustomTransitionPage<void> fadeThroughPage({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondary, child) {
      // No movement for someone who asked their phone for less (spec §11).
      if (MediaQuery.disableAnimationsOf(context)) return child;

      // Standard easing, as the spec asks.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Easing.emphasizedDecelerate,
        reverseCurve: Easing.emphasizedAccelerate,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The 3-destination navigation from spec §10: a bottom bar on phones, a
/// side rail once there is room for one.
class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Groups'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: shell.goBranch,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              leading: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 24),
                child: BrandMark(size: 28),
              ),
              destinations: [
                for (final (icon, selected, label) in _items)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: shell.goBranch,
          destinations: [
            for (final (icon, selected, label) in _items)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}
