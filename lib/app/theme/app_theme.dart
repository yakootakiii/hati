import 'package:flutter/material.dart';

import 'semantic_colors.dart';

// ---------------------------------------------------------------------------
// Design tokens (DECISIONS D-59)
//
// One accent — the teal of the app icon — on warm neutrals. Strong colour is
// kept for the primary action and for money status; everything else is ink,
// muted ink and hairlines.
// ---------------------------------------------------------------------------

/// The brand teal, as on the app icon and splash (spec §11).
const Color kBrandSeed = Color(0xFF00897B);

/// 8dp spacing grid; 16dp page padding (spec §11).
const double kSpace = 8;
const EdgeInsets kPagePadding = EdgeInsets.all(16);

/// Corner radii. Small for chips and tags, medium for controls, large for
/// containers, extra-large only for sheets and dialogs — nothing is a pill.
const double kRadiusSm = 6;
const double kRadiusMd = 10;
const double kRadiusLg = 14;
const double kRadiusXl = 20;

/// The widest a reading column gets on a tablet or desktop.
const double kContentMaxWidth = 720;

/// Motion: short, and only where it explains a change of state.
const Duration kMotionFast = Duration(milliseconds: 120);
const Duration kMotionBase = Duration(milliseconds: 200);

/// The hand-tuned palettes. Contrast is checked against the surfaces they sit
/// on: muted ink is ≥ 4.5:1 on the page background in both modes.
abstract final class _Palette {
  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0F766E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE3F3F0),
    onPrimaryContainer: Color(0xFF0B4F4A),
    secondary: Color(0xFF44403C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEFEEEC),
    onSecondaryContainer: Color(0xFF1C1917),
    tertiary: Color(0xFF067647),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE7F6EC),
    onTertiaryContainer: Color(0xFF05532F),
    error: Color(0xFFB42318),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDEDEC),
    onErrorContainer: Color(0xFF7A1A12),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1C1917),
    onSurfaceVariant: Color(0xFF66615C),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFAF9),
    surfaceContainer: Color(0xFFF6F5F3),
    surfaceContainerHigh: Color(0xFFF0EFED),
    surfaceContainerHighest: Color(0xFFE9E7E4),
    outline: Color(0xFFD3D0CC),
    outlineVariant: Color(0xFFE7E5E2),
    inverseSurface: Color(0xFF1C1917),
    onInverseSurface: Color(0xFFF5F5F4),
    inversePrimary: Color(0xFF5FD3C3),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF4FD1C0),
    onPrimary: Color(0xFF032B28),
    primaryContainer: Color(0xFF10332F),
    onPrimaryContainer: Color(0xFFB4EEE5),
    secondary: Color(0xFFD6D3D1),
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFF292826),
    onSecondaryContainer: Color(0xFFF2F1EF),
    tertiary: Color(0xFF47CD89),
    onTertiary: Color(0xFF052E1A),
    tertiaryContainer: Color(0xFF0E2C1D),
    onTertiaryContainer: Color(0xFFB8F0D0),
    error: Color(0xFFF97066),
    onError: Color(0xFF3D0A06),
    errorContainer: Color(0xFF3A1513),
    onErrorContainer: Color(0xFFFECDCA),
    surface: Color(0xFF171716),
    onSurface: Color(0xFFF2F1EF),
    onSurfaceVariant: Color(0xFFA29E99),
    surfaceContainerLowest: Color(0xFF0E0E0D),
    surfaceContainerLow: Color(0xFF141413),
    surfaceContainer: Color(0xFF1C1B1A),
    surfaceContainerHigh: Color(0xFF242321),
    surfaceContainerHighest: Color(0xFF2D2C2A),
    outline: Color(0xFF45423F),
    outlineVariant: Color(0xFF2B2A28),
    inverseSurface: Color(0xFFF2F1EF),
    onInverseSurface: Color(0xFF1C1917),
    inversePrimary: Color(0xFF0F766E),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  /// The page behind grouped content: a step below the surface in light mode,
  /// the darkest step in dark mode.
  static Color canvas(Brightness b) => b == Brightness.light
      ? const Color(0xFFF6F5F3)
      : const Color(0xFF0E0E0D);
}

abstract final class AppTheme {
  /// The colour scheme for [brightness]. Fixed rather than taken from the
  /// wallpaper, so Hati looks like Hati on every phone (DECISIONS D-59).
  static ColorScheme schemeFor(Brightness brightness) =>
      brightness == Brightness.light ? _Palette.light : _Palette.dark;

  static ThemeData build({required Brightness brightness}) {
    final scheme = schemeFor(brightness);
    final canvas = _Palette.canvas(brightness);
    final text = _textTheme(scheme);

    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(kRadiusMd)),
    );
    final hairline = BorderSide(color: scheme.outlineVariant);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Inter',
      textTheme: text,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkRipple.splashFactory,
      extensions: [MoneyColors.fromScheme(scheme)],

      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // A hairline-soft shadow once content scrolls underneath.
        scrolledUnderElevation: 1,
        shadowColor: scheme.outline,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: text.titleLarge,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: controlShape,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: controlShape,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle:
            text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle:
            text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        dividerColor: scheme.outlineVariant,
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.04),
        ),
      ),

      // Every card — filled or outlined — is a white surface with a hairline,
      // so content groups read as one family.
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
          side: hairline,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: controlShape,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(kRadiusSm + 2)),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          shape: controlShape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusLg)),
        ),
        extendedTextStyle: text.labelLarge,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: controlShape,
          side: BorderSide(color: scheme.outline),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: text.labelLarge,
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outline,
          ),
        ),
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : scheme.surface,
        ),
        labelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => (text.bodyMedium ?? const TextStyle()).copyWith(
            color: states.contains(WidgetState.error)
                ? scheme.error
                : states.contains(WidgetState.focused)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
          ),
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        border: _inputBorder(scheme.outline),
        enabledBorder: _inputBorder(scheme.outline),
        focusedBorder: _inputBorder(scheme.primary, width: 1.5),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.5),
        disabledBorder: _inputBorder(scheme.outlineVariant),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: _menuStyle(scheme),
        textStyle: text.bodyLarge,
      ),
      menuTheme: MenuThemeData(style: _menuStyle(scheme)),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: scheme.shadow.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
          side: hairline,
        ),
        textStyle: text.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
      ),

      listTileTheme: ListTileThemeData(
        // Keeps avatar-only rows above the 48dp touch target (spec §11).
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle:
            text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        leadingAndTrailingTextStyle: text.titleSmall,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusXl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle:
            text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        textStyle: text.labelMedium?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        textStyle: text.labelSmall,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: color, width: width),
      );

  static MenuStyle _menuStyle(ColorScheme scheme) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor:
            WidgetStatePropertyAll(scheme.shadow.withValues(alpha: 0.25)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusMd),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      );

  /// A compact, deliberate type scale in Inter. Tight tracking on large sizes,
  /// neutral on body. Amounts use tabular figures so columns of pesos line up
  /// (spec §11).
  static TextTheme _textTheme(ColorScheme scheme) {
    const tabular = [FontFeature.tabularFigures()];
    final ink = scheme.onSurface;

    TextStyle s(
      double size,
      FontWeight weight, {
      double height = 1.3,
      double tracking = 0,
      bool figures = false,
    }) =>
        TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: tracking,
          color: ink,
          fontFeatures: figures ? tabular : null,
        );

    return TextTheme(
      displayLarge: s(48, FontWeight.w600, height: 1.1, tracking: -1.4, figures: true),
      displayMedium: s(40, FontWeight.w600, height: 1.1, tracking: -1.1, figures: true),
      displaySmall: s(34, FontWeight.w600, height: 1.15, tracking: -0.9, figures: true),
      headlineLarge: s(30, FontWeight.w600, height: 1.2, tracking: -0.7, figures: true),
      headlineMedium: s(26, FontWeight.w600, height: 1.2, tracking: -0.5, figures: true),
      headlineSmall: s(22, FontWeight.w600, height: 1.25, tracking: -0.35, figures: true),
      titleLarge: s(18, FontWeight.w600, height: 1.3, tracking: -0.2, figures: true),
      titleMedium: s(16, FontWeight.w600, height: 1.35, tracking: -0.1, figures: true),
      titleSmall: s(14, FontWeight.w600, height: 1.35, figures: true),
      bodyLarge: s(16, FontWeight.w400, height: 1.45, tracking: -0.1),
      bodyMedium: s(14.5, FontWeight.w400, height: 1.45, tracking: -0.05),
      bodySmall: s(13, FontWeight.w400, height: 1.4),
      labelLarge: s(14.5, FontWeight.w600, height: 1.2, tracking: -0.05),
      labelMedium: s(12.5, FontWeight.w500, height: 1.25),
      labelSmall: s(11.5, FontWeight.w500, height: 1.25, tracking: 0.1),
    );
  }
}
