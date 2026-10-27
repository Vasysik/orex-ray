import 'package:flutter/material.dart';

import 'orex_theme.dart';

/// Only seven independent colors. No theme packs or configurable gradients.
class OrexPalette extends ThemeExtension<OrexPalette> {
  const OrexPalette({
    required this.accent,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.border,
    required this.success,
    required this.danger,
  });

  static const roles = <String, String>{
    'accent': 'Акцент',
    'secondary': 'Дополнительный цвет',
    'background': 'Фон',
    'surface': 'Панели',
    'text': 'Основной текст',
    'mutedText': 'Второстепенный текст',
    'border': 'Границы',
    'success': 'Успешное соединение',
    'danger': 'Ошибка / предупреждение',
  };

  final Color accent;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color border;
  final Color success;
  final Color danger;

  static OrexPalette resolve(
    Brightness brightness,
    Map<String, Color> overrides,
  ) {
    final dark = brightness == Brightness.dark;
    Color get(String key, Color fallback) => overrides[key] ?? fallback;
    return OrexPalette(
      accent: get('accent', OrexColors.copper),
      secondary: get('secondary', OrexColors.ochre),
      background: get('background', dark ? OrexColors.darkBg : OrexColors.lightBg),
      surface: get('surface', dark ? OrexColors.darkSurface : OrexColors.lightSurface),
      text: get('text', dark ? OrexColors.darkText : OrexColors.lightText),
      mutedText: get('mutedText', dark ? OrexColors.darkTextSoft : OrexColors.lightTextSoft),
      border: get('border', (dark ? OrexColors.ochreLight : OrexColors.copperBright)
          .withValues(alpha: dark ? 0.18 : 0.28)),
      success: get('success', OrexColors.online),
      danger: get('danger', OrexColors.danger),
    );
  }

  Color role(String key) => switch (key) {
        'accent' => accent,
        'secondary' => secondary,
        'background' => background,
        'surface' => surface,
        'text' => text,
        'mutedText' => mutedText,
        'border' => border,
        'success' => success,
        'danger' => danger,
        _ => throw ArgumentError.value(key, 'key', 'Unknown color role'),
      };

  static OrexPalette of(BuildContext context) =>
      Theme.of(context).extension<OrexPalette>() ??
      resolve(Theme.of(context).brightness, const {});

  @override
  OrexPalette copyWith({
    Color? accent,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? text,
    Color? mutedText,
    Color? border,
    Color? success,
    Color? danger,
  }) => OrexPalette(
        accent: accent ?? this.accent,
        secondary: secondary ?? this.secondary,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        text: text ?? this.text,
        mutedText: mutedText ?? this.mutedText,
        border: border ?? this.border,
        success: success ?? this.success,
        danger: danger ?? this.danger,
      );

  @override
  OrexPalette lerp(ThemeExtension<OrexPalette>? other, double t) {
    if (other is! OrexPalette) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}
