/// Supabase connection details, supplied at build time.
///
/// Passed with `--dart-define-from-file=.env` so no key is ever committed and
/// nothing has to be read from disk at runtime. The publishable key is safe to
/// ship in a client build — RLS is what protects the data, not the key.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// Newer projects issue a `sb_publishable_…` key; older ones call the same
  /// thing the anon key. Either env var works.
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get publishableKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _anonKey;

  /// Where Supabase sends people back to after a password-reset email or a
  /// Google sign-in: a deep link into this app, registered in
  /// AndroidManifest.xml and Info.plist. It must also be listed under
  /// Authentication → URL Configuration → Redirect URLs in the dashboard, or
  /// Supabase falls back to the Site URL (DECISIONS D-60).
  static const String authRedirect = 'com.hati.hati://auth-callback';

  /// False until a project is linked, which lets the app boot and show a setup
  /// screen instead of crashing on a missing key.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
