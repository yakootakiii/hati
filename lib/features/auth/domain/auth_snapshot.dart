/// What the rest of the app needs to know about the session.
///
/// Deliberately not Supabase's own `Session`: the router, the screens and their
/// tests all speak this instead, so none of them depend on the auth SDK.
class AuthSnapshot {
  const AuthSnapshot({
    required this.userId,
    required this.emailConfirmed,
    this.recoveringPassword = false,
  });

  const AuthSnapshot.signedOut()
    : userId = null,
      emailConfirmed = false,
      recoveringPassword = false;

  final String? userId;

  /// True once the user has clicked the link in their verification email.
  ///
  /// With email confirmation switched on, Supabase withholds the session until
  /// then, so a signed-in user is always confirmed. The flag stays meaningful
  /// for projects where confirmation is off.
  final bool emailConfirmed;

  /// Signed in through a password-reset link and not yet given a new
  /// password. The router holds the user on the reset screen until they do.
  final bool recoveringPassword;

  bool get isSignedIn => userId != null;

  @override
  bool operator ==(Object other) =>
      other is AuthSnapshot &&
      other.userId == userId &&
      other.emailConfirmed == emailConfirmed &&
      other.recoveringPassword == recoveringPassword;

  @override
  int get hashCode => Object.hash(userId, emailConfirmed, recoveringPassword);
}
