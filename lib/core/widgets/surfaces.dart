import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Rows that belong together, on one surface with hairline dividers — instead
/// of a separate card for every row (DECISIONS D-59).
class ListGroup extends StatelessWidget {
  const ListGroup({
    required this.children,
    this.dividerIndent = 16,
    super.key,
  });

  final List<Widget> children;

  /// Where row dividers start; set it past a leading avatar so the line runs
  /// under the text, not the picture.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: dividerIndent),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A section label above content, with an optional quiet action at the end.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    this.action,
    this.padding = const EdgeInsets.fromLTRB(4, kSpace * 3, 4, kSpace),
    super.key,
  });

  final String title;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A status in words with a small dot of its colour — colour is never the
/// only signal (spec §11).
class StatusLabel extends StatelessWidget {
  const StatusLabel(this.text, {required this.color, this.style, super.key});

  final String text;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodySmall;

    final resolved =
        base?.copyWith(color: color, fontWeight: FontWeight.w500);
    final lineHeight =
        (resolved?.fontSize ?? 13) * (resolved?.height ?? 1.4) *
            MediaQuery.textScalerOf(context).scale(1);

    // The text is plain (and wraps on a narrow row); the dot sits in its
    // left padding, centred on the first line.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(text, style: resolved),
        ),
        Positioned(
          left: 0,
          top: (lineHeight - 6) / 2,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

/// A small neutral tag, e.g. "Default". Quieter than a Badge, which is kept
/// for counts that need attention.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// An inline note: context the user should read, but not an error.
class InfoNote extends StatelessWidget {
  const InfoNote({
    required this.message,
    this.icon = Icons.info_outline,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(kSpace * 1.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: kSpace * 1.5),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a page's content to a readable column on tablets and desktop, and
/// does nothing on a phone.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    required this.child,
    this.maxWidth = kContentMaxWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// The Hati mark from the app icon: a disc cut in two, the halves slid past
/// each other along the cut (DECISIONS D-54).
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _BrandMarkPainter(
          color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Proportions taken from the 1024px icon: radius 222, gap 62, offset 77.
    final unit = size.width / 520;
    final radius = 222 * unit;
    final gap = 31 * unit;
    final slide = 38 * unit;
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = color;

    // Left half, slid down.
    canvas.drawArc(
      Rect.fromCircle(
        center: centre.translate(-gap, slide),
        radius: radius,
      ),
      math.pi / 2,
      math.pi,
      true,
      paint,
    );
    // Right half, slid up.
    canvas.drawArc(
      Rect.fromCircle(
        center: centre.translate(gap, -slide),
        radius: radius,
      ),
      -math.pi / 2,
      math.pi,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.color != color;
}
