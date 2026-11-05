/// Why an auth attempt failed, in terms the UI can act on.
///
/// Every message is written to be shown to the user as-is: plain, specific and
/// never leaking whether an email is registered beyond what the flow already
/// reveals (spec §11 copy tone).
enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  emailAlreadyRegistered,
  weakPassword,
  rateLimited,
  network,
  notConfigured,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message);

  final AuthFailureKind kind;
  final String message;

  static const AuthFailure notConfigured = AuthFailure(
    AuthFailureKind.notConfigured,
    'This build has no Supabase project attached yet.',
  );

  @override
  String toString() => 'AuthFailure(${kind.name}): $message';
}
