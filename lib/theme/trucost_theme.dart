//
//  trucost_theme.dart
//  TruCost (Flutter)
//
//  Goes in: lib/theme/trucost_theme.dart
//
//  The color + type system — the Flutter port of the native app's
//  TruCostTheme. Five user-selectable color themes (green is the brand
//  default), a fixed brand green for splash/nav/icon, GO / NO-GO colors
//  for the Ugly Truth verdict, and the rounded display voice (Nunito)
//  wired into the text theme so headlines match the wordmark.
//
//  Build a theme for the selected id:
//      MaterialApp(theme: TruCostTheme.theme(TruCostThemeId.green))
//
//  Read brand / verdict colors anywhere:
//      final palette = Theme.of(context).extension<TruCostPalette>()!;
//      palette.brandPrimary, palette.go, palette.noGo
//
//  Standard Material colors still come from the color scheme:
//      Theme.of(context).colorScheme.primary    // selected theme's dark color
//      Theme.of(context).colorScheme.secondary  // selected theme's accent
//

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The five color themes a driver can pick (mirrors the native app).
enum TruCostThemeId { green, black, blue, red, maroon }

class TruCostTheme {
  TruCostTheme._();

  // ── Fixed brand colors ──────────────────────────────────────────────
  // Used for splash, nav, app icon — always green regardless of the
  // theme the user picks.
  static const Color brandPrimary = Color(0xFF1B5E20); // forest — matches logo
  static const Color brandAccent  = Color(0xFF76D700); // lime

  // ── Verdict colors for the Ugly Truth ───────────────────────────────
  static const Color go   = Color(0xFF34C759); // GO — balanced green
  static const Color noGo = Color(0xFFFF3B30); // NO-GO — red

  // ── App background (soft off-white, matches the native look) ─────────
  static const Color background = Color(0xFFF6F7F6);

  // ── Per-theme dark "primary" color (ported hex-for-hex) ──────────────
  static Color primary(TruCostThemeId id) {
    switch (id) {
      case TruCostThemeId.green:  return const Color(0xFF1B5E20);
      case TruCostThemeId.black:  return const Color(0xFF1C1C1E);
      case TruCostThemeId.blue:   return const Color(0xFF0B4F8B);
      case TruCostThemeId.red:    return const Color(0xFF7A0F1A);
      case TruCostThemeId.maroon: return const Color(0xFF4A0E21);
    }
  }

  // ── Per-theme bright "accent" color (ported hex-for-hex) ─────────────
  static Color accent(TruCostThemeId id) {
    switch (id) {
      case TruCostThemeId.green:  return const Color(0xFF76D700);
      case TruCostThemeId.black:  return const Color(0xFF5E5E63);
      case TruCostThemeId.blue:   return const Color(0xFF40A9FF);
      case TruCostThemeId.red:    return const Color(0xFFFF4D4D);
      case TruCostThemeId.maroon: return const Color(0xFFD64B6A);
    }
  }

  static String displayName(TruCostThemeId id) {
    switch (id) {
      case TruCostThemeId.green:  return 'Green';
      case TruCostThemeId.black:  return 'Black';
      case TruCostThemeId.blue:   return 'Blue';
      case TruCostThemeId.red:    return 'Red';
      case TruCostThemeId.maroon: return 'Maroon';
    }
  }

  /// Build the full ThemeData for a selected theme id.
  static ThemeData theme(TruCostThemeId id) {
    final Color p = primary(id);
    final Color a = accent(id);

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: p,
      primary: p,
      secondary: a,
      brightness: Brightness.light,
    );

    // Rounded display voice (Nunito). Body stays Nunito too for one cohesive
    // family; display / headline / title styles go heavy. We bump weight on
    // the existing styles so their default sizes are preserved.
    final TextTheme tt = GoogleFonts.nunitoTextTheme();
    final TextTheme rounded = tt.copyWith(
      displayLarge:   tt.displayLarge?.copyWith(fontWeight: FontWeight.w800),
      displayMedium:  tt.displayMedium?.copyWith(fontWeight: FontWeight.w800),
      displaySmall:   tt.displaySmall?.copyWith(fontWeight: FontWeight.w800),
      headlineLarge:  tt.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall:  tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge:     tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium:    tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: rounded,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: p,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        TruCostPalette(
          brandPrimary: brandPrimary,
          brandAccent: brandAccent,
          go: go,
          noGo: noGo,
          themePrimary: p,
          themeAccent: a,
        ),
      ],
    );
  }

  /// The big hero number on the Ugly Truth screen — rounded, heavy.
  static TextStyle heroNumber(Color color) => GoogleFonts.nunito(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        color: color,
      );

  /// The "THE UGLY TRUTH" banner headline.
  static TextStyle bannerTitle(Color color) => GoogleFonts.nunito(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: color,
      );
}

/// Brand + verdict colors carried on the theme so any screen can read them
/// without importing hard-coded literals.
@immutable
class TruCostPalette extends ThemeExtension<TruCostPalette> {
  final Color brandPrimary;
  final Color brandAccent;
  final Color go;
  final Color noGo;
  final Color themePrimary;
  final Color themeAccent;

  const TruCostPalette({
    required this.brandPrimary,
    required this.brandAccent,
    required this.go,
    required this.noGo,
    required this.themePrimary,
    required this.themeAccent,
  });

  @override
  TruCostPalette copyWith({
    Color? brandPrimary,
    Color? brandAccent,
    Color? go,
    Color? noGo,
    Color? themePrimary,
    Color? themeAccent,
  }) {
    return TruCostPalette(
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandAccent: brandAccent ?? this.brandAccent,
      go: go ?? this.go,
      noGo: noGo ?? this.noGo,
      themePrimary: themePrimary ?? this.themePrimary,
      themeAccent: themeAccent ?? this.themeAccent,
    );
  }

  @override
  TruCostPalette lerp(ThemeExtension<TruCostPalette>? other, double t) {
    if (other is! TruCostPalette) return this;
    return TruCostPalette(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      go: Color.lerp(go, other.go, t)!,
      noGo: Color.lerp(noGo, other.noGo, t)!,
      themePrimary: Color.lerp(themePrimary, other.themePrimary, t)!,
      themeAccent: Color.lerp(themeAccent, other.themeAccent, t)!,
    );
  }
}
