import 'package:flutter/material.dart';

import 'dex_accent.dart';
import 'dex_colors.dart';
import 'dex_glass.dart';
import 'dex_tokens.dart';

/// Assembles [ThemeData] for DroidPier from the design tokens.
///
/// Both brightnesses are first-class: the light theme is a full parity
/// translation, not a washed-out dark theme.
abstract final class DexTheme {
  static ThemeData dark({int accentIndex = 0}) => _build(
    Brightness.dark,
    withAccent(DexColors.dark, accentIndex, Brightness.dark),
    DexGlass.dark,
  );

  static ThemeData light({int accentIndex = 0}) => _build(
    Brightness.light,
    withAccent(DexColors.light, accentIndex, Brightness.light),
    DexGlass.light,
  );

  static ThemeData _build(Brightness brightness, DexColors c, DexGlass g) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.signal,
      onPrimary: brightness == Brightness.dark ? c.bg : Colors.white,
      secondary: c.trace,
      onSecondary: brightness == Brightness.dark ? c.bg : Colors.white,
      error: c.fault,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.surface,
      dividerColor: c.line,
      extensions: <ThemeExtension<dynamic>>[c, g],
      textTheme: _textTheme(c),
      dividerTheme: DividerThemeData(
        color: c.line,
        thickness: DexStroke.hairline,
        space: DexStroke.hairline,
      ),
      cardTheme: CardThemeData(
        color: c.raised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line, width: DexStroke.hairline),
          borderRadius: BorderRadius.circular(DexRadius.card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.raised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line, width: DexStroke.hairline),
          borderRadius: BorderRadius.circular(DexRadius.dialog),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.signal,
          foregroundColor: brightness == Brightness.dark ? c.bg : Colors.white,
          minimumSize: const Size(0, DexHit.primary),
          padding: const EdgeInsets.symmetric(horizontal: DexSpace.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DexRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.line, width: DexStroke.hairline),
          minimumSize: const Size(0, DexHit.primary),
          padding: const EdgeInsets.symmetric(horizontal: DexSpace.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DexRadius.control),
          ),
        ),
      ),
      // Focus must always be visible and must out-contrast rest state.
      focusColor: c.signal,
      splashFactory: NoSplash.splashFactory,
    );
  }

  static TextTheme _textTheme(DexColors c) {
    TextStyle display(double size, FontWeight weight) => TextStyle(
      fontFamily: DexType.display,
      fontFamilyFallback: DexType.displayFallback,
      fontSize: size,
      fontWeight: weight,
      height: 1.2,
      letterSpacing: -0.2,
      color: c.text,
    );

    TextStyle body(double size, FontWeight weight, Color color) => TextStyle(
      fontFamily: DexType.body,
      fontFamilyFallback: DexType.bodyFallback,
      fontSize: size,
      fontWeight: weight,
      height: 1.45,
      color: color,
    );

    // Every slot is filled deliberately. An undefined slot does not fail
    // loudly — it silently falls through to Material's default family, which
    // is not bundled. In production that reads as a system font in the middle
    // of the type system; in goldens it renders as tofu boxes. Two widgets
    // have already shipped that way (`headlineSmall`, then `labelMedium`), so
    // the gaps are closed rather than patched at each call site.
    return TextTheme(
      displayLarge: display(44, FontWeight.w600),
      displayMedium: display(38, FontWeight.w600),
      displaySmall: display(32, FontWeight.w600),
      headlineLarge: display(28, FontWeight.w600),
      headlineMedium: display(24, FontWeight.w600),
      headlineSmall: display(20, FontWeight.w600),
      titleLarge: display(20, FontWeight.w500),
      titleMedium: body(16, FontWeight.w500, c.text),
      titleSmall: body(14, FontWeight.w500, c.text),
      bodyLarge: body(15, FontWeight.w400, c.text),
      bodyMedium: body(13, FontWeight.w400, c.text),
      bodySmall: body(11, FontWeight.w400, c.muted),
      labelLarge: body(13, FontWeight.w500, c.text),
      labelMedium: body(12, FontWeight.w500, c.text),
      labelSmall: body(11, FontWeight.w400, c.muted),
    );
  }

  /// Machine values — serials, ports, latency, throughput, error codes.
  ///
  /// Always tabular so continuously updating numbers do not jitter.
  static TextStyle data(DexColors c, {double size = 13, Color? color}) {
    return TextStyle(
      fontFamily: DexType.data,
      fontFamilyFallback: DexType.dataFallback,
      fontSize: size,
      height: 1.4,
      color: color ?? c.muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}
