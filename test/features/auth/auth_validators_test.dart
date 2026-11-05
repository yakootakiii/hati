import 'package:flutter_test/flutter_test.dart';
import 'package:hati/features/auth/domain/auth_validators.dart';

void main() {
  group('email', () {
    test('accepts ordinary addresses', () {
      expect(AuthValidators.email('bea@example.com'), isNull);
      expect(AuthValidators.email('bea.reyes+hati@mail.co.uk'), isNull);
      expect(AuthValidators.email('  bea@example.com  '), isNull,
          reason: 'surrounding space is trimmed before sending');
    });

    test('rejects empty and malformed addresses', () {
      expect(AuthValidators.email(null), 'Enter your email');
      expect(AuthValidators.email(''), 'Enter your email');
      expect(AuthValidators.email('bea'), isNotNull);
      expect(AuthValidators.email('bea@'), isNotNull);
      expect(AuthValidators.email('bea@example'), isNotNull);
      expect(AuthValidators.email('@example.com'), isNotNull);
    });
  });

  group('password', () {
    test('requires the minimum length on sign-up', () {
      expect(AuthValidators.password('correcthorse'), isNull);
      expect(AuthValidators.password(''), 'Enter a password');
      expect(AuthValidators.password('short'), 'Use at least 8 characters');
    });

    test('only requires presence on log-in, so older accounts still work', () {
      expect(AuthValidators.loginPassword('short'), isNull);
      expect(AuthValidators.loginPassword(''), 'Enter your password');
    });
  });

  group('display name', () {
    test('matches the 1–50 character constraint on public.profiles', () {
      expect(AuthValidators.displayName('Bea'), isNull);
      expect(AuthValidators.displayName('a' * 50), isNull);
      expect(AuthValidators.displayName('a' * 51), isNotNull);
      expect(AuthValidators.displayName('   '), 'Enter your name');
    });
  });

  group('confirm password', () {
    test('must match the original', () {
      expect(AuthValidators.confirmPassword('hunter22', 'hunter22'), isNull);
      expect(AuthValidators.confirmPassword('hunter23', 'hunter22'), isNotNull);
      expect(AuthValidators.confirmPassword('', 'hunter22'), isNotNull);
    });
  });
}
