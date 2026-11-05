/// Form validation for the auth screens.
///
/// Pure functions returning the error to show, or null when the field is fine —
/// the shape Flutter's `TextFormField.validator` expects. Kept out of the
/// widgets so the rules can be unit-tested directly.
abstract final class AuthValidators {
  /// Minimum password length. Supabase's own default is 6; 8 is the shortest
  /// length still worth calling a password (DECISIONS D-14).
  static const int minPasswordLength = 8;

  /// Matches the `char_length(display_name) between 1 and 50` constraint on
  /// public.profiles.
  static const int maxDisplayNameLength = 50;

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(trimmed)) return "That doesn't look like an email";
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  /// Used on the log-in form, where any non-empty password should be sent to
  /// the server rather than rejected locally — an existing account may predate
  /// the length rule.
  static String? loginPassword(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password' : null;

  static String? displayName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your name';
    if (trimmed.length > maxDisplayNameLength) {
      return 'Keep it under $maxDisplayNameLength characters';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password';
    if (value != original) return "Those don't match";
    return null;
  }
}
