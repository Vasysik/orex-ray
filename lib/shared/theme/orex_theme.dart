import 'package:flutter/material.dart';

/// Фирменная палитра Orex: тёплое дерево, медь, охра и крем.
class OrexColors {
  OrexColors._();

  static const walnut = Color(0xFF8B5A2B);
  static const walnutDeep = Color(0xFF5E3A1A);
  static const copper = Color(0xFFD47939);
  static const copperBright = Color(0xFFEE8D3F);
  static const copperDeep = Color(0xFF854132);
  static const ochre = Color(0xFFD9A05B);
  static const ochreLight = Color(0xFFE7C18B);
  static const cream = Color(0xFFFCFAFA);

  static const lightBg = Color(0xFFF6ECDD);
  static const lightSurface = Color(0xFFFBF3E7);
  static const lightBubbleIn = Color(0xFFFFFFFF);
  static const lightBubbleOut = Color(0xFFE9B97F);
  static const lightText = Color(0xFF3A2417);
  static const lightTextSoft = Color(0xFF8A6E55);

  static const darkBg = Color(0xFF1C140E);
  static const darkBgRaised = Color(0xFF241912);
  static const darkSurface = Color(0xFF2A1D14);
  static const darkBubbleIn = Color(0xFF33241A);
  static const darkBubbleOut = Color(0xFF7A4A24);
  static const darkText = Color(0xFFF3E6D5);
  static const darkTextSoft = Color(0xFFB39A82);

  static const unread = copper;
  static const online = Color(0xFF8FB36A);
  static const danger = Color(0xFFCF6679);
  static const dangerStrong = Color(0xFFFF3347);

  static const copperGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [copperBright, copperDeep],
  );

  static const ambientDark = RadialGradient(
    center: Alignment(-0.6, -0.8),
    radius: 1.4,
    colors: [Color(0xFF3A2415), darkBg],
  );

  static const ambientLight = RadialGradient(
    center: Alignment(-0.6, -0.8),
    radius: 1.4,
    colors: [Color(0xFFFBEAD2), lightBg],
  );
}

class OrexTheme {
  OrexTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: OrexColors.copper,
      onPrimary: OrexColors.cream,
      secondary: OrexColors.ochre,
      onSecondary: OrexColors.walnutDeep,
      surface: isDark ? OrexColors.darkSurface : OrexColors.lightSurface,
      onSurface: isDark ? OrexColors.darkText : OrexColors.lightText,
      error: OrexColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? OrexColors.darkBg : OrexColors.lightBg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(isDark),
      dividerColor: (isDark ? OrexColors.ochre : OrexColors.walnut)
          .withValues(alpha: 0.12),
      iconTheme: IconThemeData(
        color: isDark ? OrexColors.ochreLight : OrexColors.walnut,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: OrexColors.copper.withValues(alpha: 0.2),
        selectedIconTheme: const IconThemeData(color: OrexColors.copper),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: OrexColors.copper.withValues(alpha: 0.2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: OrexColors.copper,
          foregroundColor: OrexColors.cream,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: OrexColors.walnutDeep,
        contentTextStyle: const TextStyle(color: OrexColors.cream),
        actionTextColor: OrexColors.ochreLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static TextTheme _textTheme(bool isDark) {
    final base = isDark ? OrexColors.darkText : OrexColors.lightText;
    final soft = isDark ? OrexColors.darkTextSoft : OrexColors.lightTextSoft;
    return TextTheme(
      headlineSmall: TextStyle(
        color: base,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(color: base, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
        color: base,
        fontWeight: FontWeight.w600,
        fontSize: 15.5,
      ),
      bodyMedium: TextStyle(color: base, fontSize: 14.5, height: 1.35),
      bodySmall: TextStyle(color: soft, fontSize: 12.5),
      labelLarge: TextStyle(
        color: base,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
