import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/push/push_registration.dart';
import '../data/auth_repository.dart';
import '../domain/auth_failure.dart';

part 'auth_controller.g.dart';

/// The email awaiting verification, remembered across the hop from sign-up to
/// the "check your inbox" screen so Resend has something to send to.
@Riverpod(keepAlive: true)
class PendingVerificationEmail extends _$PendingVerificationEmail {
  @override
  String? build() => null;

  void set(String email) => state = email;
  void clear() => state = null;
}

/// Drives the auth forms.
///
/// Each action returns whether it succeeded, so a screen can navigate on true
/// while the failure surfaces through [state] as an inline message — never a
/// dialog (spec §10.1).
@riverpod
class AuthController extends _$AuthController {
  @override
  FutureOr<void> build() {}

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _run(() async {
      await ref
          .read(authRepositoryProvider)
          .signUp(email: email, password: password, displayName: displayName);
      ref.read(pendingVerificationEmailProvider.notifier).set(email.trim());
    });
  }

  Future<bool> signIn({required String email, required String password}) {
    return _run(
      () => ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password),
    );
  }

  /// Hands off to Google in the browser. True means the browser opened; the
  /// sign-in itself lands later through the deep link.
  Future<bool> signInWithGoogle() {
    return _run(() => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  Future<bool> updatePassword(String password) {
    return _run(
      () => ref.read(authRepositoryProvider).updatePassword(password),
    );
  }

  Future<bool> sendPasswordReset(String email) {
    return _run(
      () => ref.read(authRepositoryProvider).sendPasswordReset(email),
    );
  }

  Future<bool> resendConfirmation() {
    final email = ref.read(pendingVerificationEmailProvider);
    if (email == null) return Future.value(false);
    return _run(
      () => ref.read(authRepositoryProvider).resendConfirmation(email),
    );
  }

  Future<bool> signOut() {
    // Read up front: this controller can be disposed while the awaits run.
    final push = ref.read(pushRegistrationProvider.notifier);
    final auth = ref.read(authRepositoryProvider);
    final pending = ref.read(pendingVerificationEmailProvider.notifier);

    return _run(() async {
      // First, while the session still says whose phone this is (D-65).
      await push.unregister();
      await auth.signOut();
      pending.clear();
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      // Signing out can dispose this controller mid-action; nobody is left
      // to show the result to.
      if (ref.mounted) state = const AsyncValue<void>.data(null);
      return true;
    } on AuthFailure catch (failure, stackTrace) {
      if (ref.mounted) state = AsyncValue<void>.error(failure, stackTrace);
      return false;
    }
  }
}

/// The message to show for the controller's current error, or null when there
/// is nothing to show.
String? authErrorMessage(AsyncValue<void> state) {
  final error = state.error;
  if (error == null) return null;
  if (error is AuthFailure) return error.message;
  return 'Something went wrong. Try again.';
}
