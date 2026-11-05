import 'package:flutter/material.dart';

import '../images/image_models.dart';
import 'image_widgets.dart';

/// Someone's avatar: their photo if they have one, otherwise their initial.
///
/// Always carries a semantics label, because an avatar on its own is
/// meaningless to a screen reader (spec §11).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.displayName,
    this.avatarPath,
    this.radius = 20,
    this.semanticsSuffix,
    super.key,
  });

  final String displayName;
  final String? avatarPath;
  final double radius;

  /// Appended to the name, e.g. "owes ₱3,125, unpaid" (spec §11).
  final String? semanticsSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = semanticsSuffix == null
        ? displayName
        : '$displayName, $semanticsSuffix';
    final path = avatarPath;

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: radius * 2,
        child: ClipOval(
          child: path == null || path.isEmpty
              ? Container(
                  color: theme.colorScheme.secondaryContainer,
                  alignment: Alignment.center,
                  child: Text(
                    _initial,
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontSize: radius * 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : AttachmentImage(
                  bucket: StorageBucket.avatars,
                  path: path,
                  width: radius * 2,
                  height: radius * 2,
                  enlargeOnTap: false,
                ),
        ),
      ),
    );
  }

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }
}
