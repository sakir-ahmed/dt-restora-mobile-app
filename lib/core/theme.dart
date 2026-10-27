import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand tokens, mirrored from the web app's `resources/css/app.css`
/// (Datatech Blue, Midnight Navy, Bright Sky, Slate, Cloud).
class Brand {
  static const Color primary = Color(0xFF0B63CE);
  static const Color navy = Color(0xFF0A1428);
  static const Color accent = Color(0xFF38A8FF);
  static const Color slate = Color(0xFF4A5568);
  static const Color soft = Color(0xFFAFC0D6);
  static const Color cloud = Color(0xFFF5F7FA);
  static const Color border = Color(0xFFDFE6F0);

  static const Color darkSurface = Color(0xFF101D36);
  static const Color darkBorder = Color(0xFF22345A);

  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFE11D48);
  static const Color warning = Color(0xFFD97706);
}

/// Colors that change between the light and dark themes. Use these in
/// widgets instead of the fixed [Brand] constants.
extension BrandContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Secondary text (Slate / Soft Grey).
  Color get muted => isDark ? Brand.soft : Brand.slate;

  /// Primary text (Midnight Navy / Cloud).
  Color get fg => isDark ? Brand.cloud : Brand.navy;

  /// Page background (Cloud / Midnight Navy).
  Color get pageBg => isDark ? Brand.navy : Brand.cloud;

  Color get lineColor => isDark ? Brand.darkBorder : Brand.border;

  /// Brand blue; lighter in dark mode so it stays readable.
  Color get brand => isDark ? Brand.accent : Brand.primary;

  /// Soft tinted background for notices, e.g. the offline banner.
  Color get warnBg => Brand.warning.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get warnFg => isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
}

/// Accent per module group, mirroring the admin panel's sidebar colours:
/// Sales blue, Inventory emerald, People violet, Finance amber.
Color groupColor(BuildContext context, String group) {
  final dark = context.isDark;
  switch (group) {
    case 'Sales':
      return dark ? Brand.accent : Brand.primary;
    case 'Inventory':
      return dark ? const Color(0xFF34D399) : const Color(0xFF059669);
    case 'People':
      return dark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    case 'Finance':
      return dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    default:
      return dark ? Brand.soft : Brand.slate;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = dark
      ? const ColorScheme.dark(
          primary: Brand.accent,
          onPrimary: Brand.navy,
          secondary: Brand.accent,
          onSecondary: Brand.navy,
          surface: Brand.darkSurface,
          onSurface: Brand.cloud,
          onSurfaceVariant: Brand.soft,
          outline: Brand.darkBorder,
          outlineVariant: Brand.darkBorder,
          error: Color(0xFFFB7185),
          primaryContainer: Color(0xFF1B3C6E),
          onPrimaryContainer: Brand.cloud,
          secondaryContainer: Color(0xFF1B3C6E),
          onSecondaryContainer: Brand.cloud,
          surfaceContainerHighest: Color(0xFF16264A),
        )
      : const ColorScheme.light(
          primary: Brand.primary,
          onPrimary: Colors.white,
          secondary: Brand.accent,
          onSecondary: Brand.navy,
          surface: Colors.white,
          onSurface: Brand.navy,
          onSurfaceVariant: Brand.slate,
          outline: Brand.border,
          outlineVariant: Brand.border,
          error: Brand.danger,
          primaryContainer: Color(0xFFDCEAFB),
          onPrimaryContainer: Brand.navy,
          secondaryContainer: Color(0xFFDCEAFB),
          onSecondaryContainer: Brand.primary,
          surfaceContainerHighest: Color(0xFFEAF0F8),
        );

  final bg = dark ? Brand.navy : Brand.cloud;
  final line = dark ? Brand.darkBorder : Brand.border;

  // Inter for body text, Poppins for headlines, Hind Siliguri for Bangla.
  final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
  final bangla = GoogleFonts.hindSiliguri().fontFamily;
  TextTheme withFallback(TextTheme t) => t.apply(fontFamilyFallback: [?bangla]);
  final body = withFallback(GoogleFonts.interTextTheme(base));
  final textTheme = body.copyWith(
    displayLarge: GoogleFonts.poppins(textStyle: body.displayLarge, fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.poppins(textStyle: body.displayMedium, fontWeight: FontWeight.w700),
    displaySmall: GoogleFonts.poppins(textStyle: body.displaySmall, fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.poppins(textStyle: body.headlineLarge, fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.poppins(textStyle: body.headlineMedium, fontWeight: FontWeight.w700),
    headlineSmall: GoogleFonts.poppins(textStyle: body.headlineSmall, fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.poppins(textStyle: body.titleLarge, fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.poppins(textStyle: body.titleMedium, fontWeight: FontWeight.w600),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: bg,
    dividerColor: line,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? Brand.darkSurface : Brand.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: line),
      selectedColor: scheme.primary.withValues(alpha: dark ? 0.25 : 0.14),
      backgroundColor: scheme.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surface),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Brand.darkBorder : Brand.navy,
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Brand.soft,
      indicatorColor: Brand.accent,
    ),
    listTileTheme: ListTileThemeData(iconColor: scheme.primary),
  );
}
