import 'package:flutter/material.dart';

import 'blackgrid_tokens.dart';
import 'ember_tokens.dart';

/// Builds Blackgrid's Material [ThemeData] for one room.
///
/// Material widgets pick up the [ColorScheme]; Ember-specific roles (hairlines,
/// the three ink levels, prose, Ember Glow/Thread, status triplets) are read
/// from the [EmberColors] extension, and Blackgrid's own roles (verdict
/// greens, map ground) from the [BlackgridColors] extension.
ThemeData blackgridTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? EmberColors.dark : EmberColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.accentInk,
    secondary: c.accentText,
    onSecondary: c.accentInk,
    error: c.errInk,
    onError: c.canvas,
    surface: c.canvas,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSecondary,
    surfaceContainerLow: c.panel,
    surfaceContainer: c.raised,
    surfaceContainerHigh: c.hover,
    surfaceContainerHighest: c.press,
    outline: c.hairlineStrong,
    outlineVariant: c.hairline,
  );
  const pill = StadiumBorder();
  final hairline = BorderSide(color: c.hairlineStrong);
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    dividerColor: c.hairline,
    fontFamily: EmberType.sans,
    textTheme: TextTheme(
      displaySmall: EmberType.display.copyWith(color: c.ink),
      headlineSmall: EmberType.headline.copyWith(color: c.ink),
      titleLarge: EmberType.title.copyWith(color: c.ink),
      bodyLarge: EmberType.prose.copyWith(color: c.prose),
      bodyMedium: EmberType.body.copyWith(color: c.ink),
      titleSmall: EmberType.uiHeading.copyWith(color: c.ink),
      labelLarge: EmberType.control.copyWith(color: c.ink),
      labelSmall: EmberType.label.copyWith(color: c.inkTertiary),
      bodySmall: EmberType.label.copyWith(color: c.inkSecondary),
      titleMedium: EmberType.uiHeading.copyWith(color: c.ink),
    ),
    // One motion family: no ink splashes, no hover fades.
    splashFactory: NoSplash.splashFactory,
    hoverColor: c.hover,
    focusColor: c.accentSoft,
    highlightColor: Colors.transparent,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        minimumSize: const Size(0, EmberSize.control),
        padding: const EdgeInsets.symmetric(horizontal: EmberSpace.md),
        shape: pill,
        textStyle: EmberType.control,
        animationDuration: Duration.zero,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: hairline,
        minimumSize: const Size(0, EmberSize.control),
        padding: const EdgeInsets.symmetric(horizontal: EmberSpace.md),
        shape: pill,
        textStyle: EmberType.control,
        animationDuration: Duration.zero,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.inkSecondary,
        minimumSize: const Size(0, EmberSize.control),
        padding: const EdgeInsets.symmetric(horizontal: EmberSpace.md),
        shape: pill,
        textStyle: EmberType.control,
        animationDuration: Duration.zero,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EmberRadius.m),
        borderSide: hairline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EmberRadius.m),
        borderSide: hairline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EmberRadius.m),
        borderSide: BorderSide(color: c.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EmberRadius.m),
        borderSide: BorderSide(color: c.errLine),
      ),
      hintStyle: EmberType.body.copyWith(color: c.inkTertiary),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: hairline),
      backgroundColor: Colors.transparent,
      selectedColor: c.accentSoft,
      labelStyle: EmberType.label.copyWith(color: c.inkSecondary),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.raised),
        side: WidgetStatePropertyAll(hairline),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EmberRadius.l),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.raised,
      contentTextStyle: EmberType.control.copyWith(color: c.ink),
      actionTextColor: c.accentText,
      shape: StadiumBorder(side: hairline),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.fromBorderSide(hairline),
        borderRadius: BorderRadius.circular(EmberRadius.s),
        boxShadow: dark ? EmberShadows.floatDark : EmberShadows.floatLight,
      ),
      textStyle: EmberType.body.copyWith(fontSize: 12, color: c.ink),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EmberRadius.l),
        side: hairline,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: c.inkSecondary,
        selectedForegroundColor: c.ink,
        selectedBackgroundColor: c.segmentOn,
        side: hairline,
        textStyle: EmberType.control,
        minimumSize: const Size(0, EmberSize.segment + 4),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[
      c,
      dark ? BlackgridColors.dark : BlackgridColors.light,
    ],
  );
}
