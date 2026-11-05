import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hati/app/theme/semantic_colors.dart';
import 'package:hati/features/auth/domain/auth_snapshot.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('a signed-out launch lands on Welcome', (tester) async {
    await pumpApp(tester);

    expect(find.text('Hati'), findsOneWidget);
    expect(find.text('Sign up with email'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a signed-in launch lands on the home shell', (tester) async {
    await pumpApp(tester, session: signedIn);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Sign up with email'), findsNothing);
  });

  testWidgets('signing in mid-session redirects off the auth screens',
      (tester) async {
    final harness = await pumpApp(tester);
    expect(find.byType(NavigationBar), findsNothing);

    harness.auth.signInAs('bea');
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('signing out sends the user back to Welcome', (tester) async {
    final harness = await pumpApp(tester, session: signedIn);

    harness.auth.emit(const AuthSnapshot.signedOut());
    await tester.pumpAndSettle();

    expect(find.text('Sign up with email'), findsOneWidget);
  });

  testWidgets('a signed-out user cannot reach a group', (tester) async {
    final harness = await pumpApp(tester);

    await harness.go('/groups/g1');

    expect(harness.location, '/welcome');
  });

  testWidgets('a build with no project explains itself instead of crashing',
      (tester) async {
    await pumpApp(tester, configured: false);

    expect(find.text('No Supabase project'), findsOneWidget);
  });

  testWidgets('exposes the semantic money palette in both themes',
      (tester) async {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
        brightness: brightness,
      );
      late MoneyColors colors;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: scheme,
            extensions: [MoneyColors.fromScheme(scheme)],
          ),
          home: Builder(
            builder: (context) {
              colors = context.money;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors.owe, isNot(colors.owed));
      expect(colors.pending, isNot(colors.owe));
    }
  });
}
