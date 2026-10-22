import 'package:flutter/material.dart';

import 'orex_palette.dart';

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
  static const danger = Color(0xFFB36A6A);
  static const dangerStrong = danger;

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

  static ThemeData withColors(
    Brightness brightness,
    Map<String, Color> overrides,
  ) {
    final base = _build(brightness);
    if (overrides.isEmpty) return base;
    final palette = OrexPalette.resolve(brightness, overrides);
    final onAccent = ThemeData.estimateBrightnessForColor(palette.accent) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: palette.accent,
        onPrimary: onAccent,
        secondary: palette.secondary,
        surface: palette.surface,
        onSurface: palette.text,
        onSurfaceVariant: palette.mutedText,
        outline: palette.border,
        outlineVariant: palette.border.withValues(alpha: 0.65),
        surfaceContainer: palette.surface,
        surfaceContainerLow: palette.surface,
        surfaceContainerHigh: palette.surface,
      ),
      scaffoldBackgroundColor: palette.background,
      textTheme: base.textTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ).copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(color: palette.mutedText),
      ),
      iconTheme: IconThemeData(color: palette.accent),
      listTileTheme: ListTileThemeData(
        iconColor: palette.accent,
        selectedColor: palette.accent,
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: palette.accent.withValues(alpha: 0.20),
        side: BorderSide(color: palette.border),
        labelStyle: TextStyle(color: palette.text),
        secondaryLabelStyle: TextStyle(color: onAccent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? palette.accent : null),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: palette.border),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? palette.accent : palette.mutedText),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? palette.accent : palette.mutedText),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? palette.accent.withValues(alpha: 0.34)
                : palette.border.withValues(alpha: 0.45)),
        trackOutlineColor: WidgetStatePropertyAll(palette.border),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.border.withValues(alpha: 0.5),
        thumbColor: palette.accent,
        overlayColor: palette.accent.withValues(alpha: 0.14),
        valueIndicatorColor: palette.accent,
        valueIndicatorTextStyle: TextStyle(color: onAccent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: palette.surface.withValues(alpha: 0.35),
        labelStyle: TextStyle(color: palette.mutedText),
        helperStyle: TextStyle(color: palette.mutedText),
        prefixIconColor: palette.accent,
        suffixIconColor: palette.accent,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(
          side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        ),
      ),
      dividerColor: palette.border,
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: palette.accent.withValues(alpha: 0.2),
        selectedIconTheme: IconThemeData(color: palette.accent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: palette.accent.withValues(alpha: 0.2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          backgroundColor: WidgetStatePropertyAll(palette.accent),
          foregroundColor: WidgetStatePropertyAll(onAccent),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: palette.surface,
        iconColor: palette.accent,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: palette.surface,
        contentTextStyle: TextStyle(color: palette.text),
        actionTextColor: palette.accent,
      ),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final dividerColor =
        (isDark ? OrexColors.ochreLight : OrexColors.copperBright)
            .withValues(alpha: isDark ? 0.18 : 0.28);
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
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click),
          side: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.disabled)) {
              return BorderSide(color: dividerColor);
            }
            return BorderSide(
              color: dividerColor.withValues(
                alpha: (isDark ? 0.18 : 0.28) * 0.55,
              ),
            );
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: OrexColors.copper,
          foregroundColor: OrexColors.cream,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click),
        ),
      ),
      // Consistent width and corners for all standard editors and dialogs.
      dialogTheme: DialogThemeData(
        constraints: const BoxConstraints(maxWidth: 720),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor:
            isDark ? OrexColors.darkSurface : OrexColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        iconColor: OrexColors.copper,
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
