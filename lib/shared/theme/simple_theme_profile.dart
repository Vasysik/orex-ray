import 'package:flutter/material.dart';

import 'orex_palette.dart';

/// One portable design: named colors, mascot, and three simple glass settings.
/// The gradient direction and other decorative parameters are not editable.
class SimpleThemeProfile {
  SimpleThemeProfile({
    required this.id,
    required this.name,
    required Map<String, Color> colors,
    this.mascotPath = '',
    this.builtin = false,
    this.light = false,
    this.glassOpacity = defaultGlassOpacity,
    this.glassBlur = defaultGlassBlur,
    this.glassGlow = defaultGlassGlow,
  }) : colors = Map.unmodifiable(colors) {
    validateGlass(glassOpacity, glassBlur, glassGlow);
  }

  static const defaultGlassOpacity = 0.55;
  static const defaultGlassBlur = 18.0;
  // Classic Orex does not add a panel halo; its editable copy must match.
  static const defaultGlassGlow = 0.0;

  static void validateGlass(double opacity, double blur, double glow) {
    if (!opacity.isFinite || opacity < 0.15 || opacity > 0.95 ||
        !blur.isFinite || blur < 0 || blur > 36 ||
        !glow.isFinite || glow < -0.85 || glow > 0.85) {
      throw const FormatException('Некорректные параметры стекла');
    }
  }

  final String id;
  final String name;
  final Map<String, Color> colors;
  final String mascotPath;
  final bool builtin;
  final bool light;
  final double glassOpacity;
  final double glassBlur;
  final double glassGlow;

  SimpleThemeProfile copyWith({
    String? name,
    Map<String, Color>? colors,
    String? mascotPath,
    bool? builtin,
    bool? light,
    double? glassOpacity,
    double? glassBlur,
    double? glassGlow,
  }) => SimpleThemeProfile(
        id: id,
        name: name ?? this.name,
        colors: colors ?? this.colors,
        mascotPath: mascotPath ?? this.mascotPath,
        builtin: builtin ?? this.builtin,
        light: light ?? this.light,
        glassOpacity: glassOpacity ?? this.glassOpacity,
        glassBlur: glassBlur ?? this.glassBlur,
        glassGlow: glassGlow ?? this.glassGlow,
      );

  Map<String, double> get glassJson => {
        'opacity': glassOpacity,
        'blur': glassBlur,
        'glow': glassGlow,
      };

  static (double, double, double) parseGlass(Object? source) {
    if (source == null) {
      return (defaultGlassOpacity, defaultGlassBlur, defaultGlassGlow);
    }
    if (source is! Map) {
      throw const FormatException('Некорректный блок glass');
    }
    double value(String name, double fallback) {
      final raw = source[name];
      if (raw == null) {
        return fallback;
      }
      if (raw is! num) {
        throw const FormatException('Параметр стекла должен быть числом');
      }
      return raw.toDouble();
    }
    final opacity = value('opacity', defaultGlassOpacity);
    final blur = value('blur', defaultGlassBlur);
    final glow = value('glow', defaultGlassGlow);
    validateGlass(opacity, blur, glow);
    return (opacity, blur, glow);
  }

  Map<String, Object?> toStoredJson() => {
        'id': id,
        'name': name,
        'colors': {
          for (final entry in colors.entries)
            entry.key: '#${entry.value.toARGB32().toRadixString(16).padLeft(8, '0')}',
        },
        'mascotPath': mascotPath,
        'builtin': builtin,
        'light': light,
        'glass': glassJson,
      };

  static SimpleThemeProfile fromStoredJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Неверный идентификатор или имя темы');
    }
    final (opacity, blur, glow) = parseGlass(json['glass']);
    return SimpleThemeProfile(
      id: id,
      name: name.trim(),
      colors: parseColors(json['colors']),
      mascotPath: json['mascotPath'] is String ? json['mascotPath'] as String : '',
      builtin: json['builtin'] == true,
      light: json['light'] == true,
      glassOpacity: opacity,
      glassBlur: blur,
      glassGlow: glow,
    );
  }

  static Map<String, Color> parseColors(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Некорректные цвета темы');
    }
    final parsed = <String, Color>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || !OrexPalette.roles.containsKey(entry.key)) {
        throw const FormatException('Неизвестная цветовая роль');
      }
      final hex = entry.value;
      if (hex is! String) {
        throw const FormatException('Цвет должен быть HEX');
      }
      var digits = hex.replaceFirst('#', '');
      if (!RegExp(r'^(?:[a-fA-F0-9]{6}|[a-fA-F0-9]{8})$').hasMatch(digits)) {
        throw const FormatException('Недопустимый HEX-цвет');
      }
      if (digits.length == 6) {
        digits = 'FF$digits';
      }
      parsed[entry.key as String] = Color(int.parse(digits, radix: 16));
    }
    return parsed;
  }
}
