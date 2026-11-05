import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/router.dart';
import '../auth_controller.dart';

/// "Continue with Google", per Google's branding rules: the four-colour G on
/// a neutral button, never recoloured.
///
/// Signing in finishes in the browser and comes back through the deep link,
/// where the router takes over — so all this button does is open it.
class GoogleSignInButton extends ConsumerWidget {
  const GoogleSignInButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(authControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: busy
              ? null
              : () => ref
                    .read(authControllerProvider.notifier)
                    .signInWithGoogle(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GoogleLogo(size: 18),
              SizedBox(width: 12),
              Text('Continue with Google'),
            ],
          ),
        ),
      ],
    );
  }
}

/// A rule with "or" in the middle, between Google and the email form.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace * 2.5),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// Google's "G", drawn from the paths of its official 48×48 SVG so the app
/// needs neither an image asset nor an SVG package.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({this.size = 18, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: const _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _parts = [
    (
      Color(0xFFEA4335),
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 '
          '9.5z',
    ),
    (
      Color(0xFF4285F4),
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      Color(0xFFFBBC05),
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      Color(0xFF34A853),
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 '
          '48z',
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    for (final (colour, data) in _parts) {
      canvas.drawPath(_parse(data), Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;

  /// Just enough of SVG path syntax for the logo: M, L, H, V, C, S and Z, in
  /// absolute and relative forms, with implicit repeats.
  static Path _parse(String data) {
    final tokens = RegExp(
      r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)',
    ).allMatches(data).map((m) => m.group(0)!).toList();
    final path = Path();
    var i = 0;
    var command = '';
    var x = 0.0, y = 0.0;
    var lastControlX = 0.0, lastControlY = 0.0;

    double next() => double.parse(tokens[i++]);

    while (i < tokens.length) {
      if (RegExp('[A-Za-z]').hasMatch(tokens[i])) command = tokens[i++];
      final relative = command == command.toLowerCase();
      final ox = relative ? x : 0.0, oy = relative ? y : 0.0;

      switch (command.toUpperCase()) {
        case 'M':
          x = ox + next();
          y = oy + next();
          path.moveTo(x, y);
          // Further pairs after a move are line-tos.
          command = relative ? 'l' : 'L';
        case 'L':
          x = ox + next();
          y = oy + next();
          path.lineTo(x, y);
        case 'H':
          x = ox + next();
          path.lineTo(x, y);
        case 'V':
          y = oy + next();
          path.lineTo(x, y);
        case 'C':
          final x1 = ox + next(), y1 = oy + next();
          final x2 = ox + next(), y2 = oy + next();
          x = ox + next();
          y = oy + next();
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastControlX = x2;
          lastControlY = y2;
        case 'S':
          // The first control point reflects the previous curve's second.
          final x1 = 2 * x - lastControlX, y1 = 2 * y - lastControlY;
          final x2 = ox + next(), y2 = oy + next();
          x = ox + next();
          y = oy + next();
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastControlX = x2;
          lastControlY = y2;
        case 'Z':
          path.close();
      }
    }
    return path;
  }
}

/// Legal small print with the document names as links: "…the Terms and
/// Conditions and … the Privacy Notice" (D-61, D-63).
///
/// One run of text, so it wraps like a sentence at any text size rather than
/// breaking between the words and the links.
class LegalLinksText extends StatefulWidget {
  const LegalLinksText({
    required this.lead,
    required this.middle,
    this.tail = '.',
    this.style,
    this.textAlign = TextAlign.center,
    super.key,
  });

  /// Text before "Terms and Conditions".
  final String lead;

  /// Text between the two links.
  final String middle;
  final String tail;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<LegalLinksText> createState() => _LegalLinksTextState();
}

class _LegalLinksTextState extends State<LegalLinksText> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => context.push(Routes.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => context.push(Routes.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: widget.lead),
          TextSpan(
            text: 'Terms and Conditions',
            recognizer: _terms,
            style: link,
          ),
          TextSpan(text: widget.middle),
          TextSpan(text: 'Privacy Notice', recognizer: _privacy, style: link),
          TextSpan(text: widget.tail),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}

/// The small print pinned to the bottom of the auth screens.
class TermsNotice extends StatelessWidget {
  const TermsNotice({
    this.lead = 'By continuing, you agree to the ',
    super.key,
  });

  final String lead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, kSpace, 24, kSpace * 2),
      child: LegalLinksText(
        lead: lead,
        middle: ' and acknowledge the ',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      ),
    );
  }
}
