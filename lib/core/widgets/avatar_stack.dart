import 'package:flutter/material.dart';

import 'user_avatar.dart';

/// One person in an [AvatarStack].
class StackedAvatar {
  const StackedAvatar({required this.displayName, this.avatarPath});

  final String displayName;
  final String? avatarPath;
}

/// Overlapping member avatars, as on the group cards (spec §10).
///
/// The whole stack carries one semantics label rather than one per circle, so
/// a screen reader says "Bea, Carlo and 2 others" instead of reading four
/// separate letters.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    required this.people,
    this.total,
    this.radius = 16,
    super.key,
  });

  /// Convenience for callers that have only names.
  factory AvatarStack.fromNames(
    List<String> names, {
    int? total,
    double radius = 16,
  }) =>
      AvatarStack(
        people: [for (final n in names) StackedAvatar(displayName: n)],
        total: total,
        radius: radius,
      );

  final List<StackedAvatar> people;

  /// Total members, when more exist than there are [people] to show.
  final int? total;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final shown = people.take(4).toList();
    final overflow = (total ?? people.length) - shown.length;

    return Semantics(
      label: _label(shown, overflow),
      excludeSemantics: true,
      child: SizedBox(
        height: radius * 2,
        width: radius * 2 + (shown.length - 1 + (overflow > 0 ? 1 : 0)) * radius * 1.3,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * radius * 1.3,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: UserAvatar(
                    displayName: shown[i].displayName,
                    avatarPath: shown[i].avatarPath,
                    radius: radius - 2,
                  ),
                ),
              ),
            if (overflow > 0)
              Positioned(
                left: shown.length * radius * 1.3,
                child: _Circle(
                  radius: radius,
                  background: scheme.surfaceContainerHighest,
                  foreground: scheme.onSurfaceVariant,
                  label: '+$overflow',
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _label(List<StackedAvatar> shown, int overflow) {
    final base = shown.map((p) => p.displayName).join(', ');
    if (overflow <= 0) return base;
    return '$base and $overflow ${overflow == 1 ? 'other' : 'others'}';
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.radius,
    required this.background,
    required this.foreground,
    required this.label,
  });

  final double radius;
  final Color background;
  final Color foreground;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
