import 'dart:async';
import 'dart:io' show SocketException;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../legal/terms_content.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_snapshot.dart';

part 'auth_repository.g.dart';

/// Everything the app does with sessions.
///
/// An interface rather than a concrete class so the router and the screens can
/// be driven by a fake in tests without a live Supabase project.
abstract interface class AuthRepository {
  AuthSnapshot get snapshot;

  /// Emits on sign-in, sign-out, token refresh and user updates.
  Stream<AuthSnapshot> get changes;

  /// Creates the account. [displayName] travels in the user metadata, where
  /// the `handle_new_user` trigger reads it to build the profile row.
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signIn({required String email, required String password});

  /// Opens Google's sign-in in the browser. The session arrives later,
  /// through the deep link, as an ordinary sign-in on [changes].
  ///
  /// An existing account with the same verified email is the same account:
  /// Supabase links the Google identity to it.
  Future<void> signInWithGoogle();

  /// Emails a reset link that opens this app (SupabaseConfig.authRedirect).
  Future<void> sendPasswordReset(String email);

  /// Sets a new password for the signed-in user — the end of the reset flow.
  Future<void> updatePassword(String password);

  Future<void> resendConfirmation(String email);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  /// Set by the passwordRecovery event, cleared once a new password is saved
  /// or the user signs out. Supabase reports recovery only as an event, so
  /// the repository has to remember it.
  bool _recovering = false;
  bool _passwordUpdateInFlight = false;

  @override
  AuthSnapshot get snapshot => _toSnapshot(_auth.currentSession);

  @override
  Stream<AuthSnapshot> get changes => _auth.onAuthStateChange.map((state) {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        _recovering = true;
      case AuthChangeEvent.signedOut:
        _recovering = false;
      case AuthChangeEvent.userUpdated when _passwordUpdateInFlight:
        _recovering = false;
      default:
        break;
    }
    return _toSnapshot(state.session);
  });

  AuthSnapshot _toSnapshot(Session? session) {
    final user = session?.user;
    if (user == null) return const AuthSnapshot.signedOut();
    return AuthSnapshot(
      userId: user.id,
      emailConfirmed: user.emailConfirmedAt != null,
      recoveringPassword: _recovering,
    );
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _guard(() async {
      await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'display_name': displayName.trim(),
          // Which Terms they ticked, kept with the account (D-61).
          'terms_version': kTermsVersion,
        },
        // The verification link opens the app and signs them straight in,
        // instead of landing on the Site URL (DECISIONS D-60).
        emailRedirectTo: SupabaseConfig.authRedirect,
      );
    });
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    return _guard(() async {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    });
  }

  @override
  Future<void> signInWithGoogle() {
    return _guard(() async {
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.authRedirect,
        // The system browser, so Google sees the sign-ins the user already
        // has there instead of asking for a password in a fresh web view.
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    });
  }

  @override
  Future<void> sendPasswordReset(String email) {
    // Without redirectTo, Supabase links to the project's Site URL — which
    // was localhost:3000, a page that does not exist on a phone.
    return _guard(
      () => _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: SupabaseConfig.authRedirect,
      ),
    );
  }

  @override
  Future<void> updatePassword(String password) {
    return _guard(() async {
      _passwordUpdateInFlight = true;
      try {
        await _auth.updateUser(UserAttributes(password: password));
        _recovering = false;
      } finally {
        _passwordUpdateInFlight = false;
      }
    });
  }

  @override
  Future<void> resendConfirmation(String email) {
    return _guard(
      () => _auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: SupabaseConfig.authRedirect,
      ),
    );
  }

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  /// Translates SDK errors into [AuthFailure] so no screen ever has to read a
  /// raw `AuthException`.
  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException catch (error) {
      throw _mapAuthException(error);
    } on SocketException catch (_) {
      throw const AuthFailure(
        AuthFailureKind.network,
        "Can't reach Hati right now. Check your connection and try again.",
      );
    }
  }

  static AuthFailure _mapAuthException(AuthException error) {
    // Supabase reports a stable `code` on recent versions; the message is the
    // fallback for older ones.
    final code = error.code ?? '';
    final message = error.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return const AuthFailure(
        AuthFailureKind.invalidCredentials,
        "That email and password don't match an account.",
      );
    }
    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return const AuthFailure(
        AuthFailureKind.emailNotConfirmed,
        'Verify your email first — check your inbox for the link.',
      );
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return const AuthFailure(
        AuthFailureKind.emailAlreadyRegistered,
        'That email already has an account. Try logging in.',
      );
    }
    if (code == 'same_password') {
      return const AuthFailure(
        AuthFailureKind.weakPassword,
        "That's your current password. Choose a new one.",
      );
    }
    if (code == 'weak_password' || message.contains('password')) {
      return AuthFailure(AuthFailureKind.weakPassword, error.message);
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        error.statusCode == '429') {
      return const AuthFailure(
        AuthFailureKind.rateLimited,
        'Too many tries. Give it a minute and go again.',
      );
    }
    return AuthFailure(AuthFailureKind.unknown, error.message);
  }
}

/// Stands in when the build has no Supabase project attached, so the app can
/// still boot and explain itself instead of crashing at startup.
class UnconfiguredAuthRepository implements AuthRepository {
  @override
  AuthSnapshot get snapshot => const AuthSnapshot.signedOut();

  @override
  Stream<AuthSnapshot> get changes => const Stream<AuthSnapshot>.empty();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async => throw AuthFailure.notConfigured;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => throw AuthFailure.notConfigured;

  @override
  Future<void> signInWithGoogle() async => throw AuthFailure.notConfigured;

  @override
  Future<void> sendPasswordReset(String email) async =>
      throw AuthFailure.notConfigured;

  @override
  Future<void> updatePassword(String password) async =>
      throw AuthFailure.notConfigured;

  @override
  Future<void> resendConfirmation(String email) async =>
      throw AuthFailure.notConfigured;

  @override
  Future<void> signOut() async {}
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  if (!ref.watch(isBackendConfiguredProvider)) {
    return UnconfiguredAuthRepository();
  }
  return SupabaseAuthRepository(Supabase.instance.client.auth);
}

/// The current session, kept in sync with the auth stream.
///
/// Read synchronously by the router's redirect; watched by screens that care.
@Riverpod(keepAlive: true)
class SessionState extends _$SessionState {
  @override
  AuthSnapshot build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((next) => state = next);
    ref.onDispose(subscription.cancel);
    return repository.snapshot;
  }
}
