import 'dart:ui';

import 'package:flutter/material.dart';

import 'orex_palette.dart';
import 'orex_theme.dart';

/// One app-wide switch that applies to panels, including modal routes.
class OrexGlassAppearance extends ThemeExtension<OrexGlassAppearance> {
  const OrexGlassAppearance({
    this.enabled = true,
    this.opacity,
    this.blur,
    this.glow = 0,
  });

  final bool enabled;
  /// Null means use the existing panel-specific default.
  final double? opacity;
  final double? blur;
  final double glow;

  @override
  OrexGlassAppearance copyWith({
    bool? enabled,
    double? opacity,
    double? blur,
    double? glow,
  }) => OrexGlassAppearance(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        blur: blur ?? this.blur,
        glow: glow ?? this.glow,
      );

  @override
  OrexGlassAppearance lerp(ThemeExtension<OrexGlassAppearance>? other, double t) {
    if (other is! OrexGlassAppearance) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

/// Visual roles, not arbitrary per-screen modal alpha values.
class OrexGlassOpacity {
  OrexGlassOpacity._();

  static const panel = 0.55;
  static const modal = 0.55;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 18,
    this.opacity = OrexGlassOpacity.panel,
    this.padding,
    this.tint,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = OrexPalette.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appearance = theme.extension<OrexGlassAppearance>();
    final glassEnabled = appearance?.enabled ?? true;
    final effectiveOpacity = appearance?.opacity ?? opacity;
    final effectiveBlur = appearance?.blur ?? blur;
    final glow = appearance?.glow ?? 0.0;
    final baseColor = palette.surface;
    final flatColor = tint == null
        ? baseColor
        : Color.alphaBlend(tint!.withValues(alpha: 0.14), baseColor);
    final glassColor = (tint ??
            ((palette.surface == (isDark ? OrexColors.darkSurface : OrexColors.lightSurface))
                ? (isDark ? OrexColors.darkSurface : OrexColors.cream)
                : palette.surface))
        .withValues(alpha: effectiveOpacity);
    final borderColor = palette.border;

    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glassEnabled ? glassColor : flatColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
        gradient: glassEnabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.04 : 0.20),
                  Colors.transparent,
                ],
              )
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (!glassEnabled) {
      return panel;
    }
    final filter = ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur);
    final grouped = BackdropGroup.of(context) != null;

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: grouped
          ? BackdropFilter.grouped(filter: filter, child: panel)
          : BackdropFilter(filter: filter, child: panel),
    );
    if (glow == 0) {
      return clipped;
    }
    // Signed halo: negative values cast a dark shadow, positive values
    // produce an accent-colored glow. Zero preserves classic Orex panels.
    final strength = glow.abs().clamp(0.0, 0.85);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: glow < 0
                ? Colors.black.withValues(alpha: strength * 0.42)
                : palette.accent.withValues(alpha: strength * 0.22),
            blurRadius: 12 + strength * 26,
            spreadRadius: strength * 2,
          ),
        ],
      ),
      child: clipped,
    );
  }
}

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = OrexPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final original = palette.accent == OrexColors.copper &&
        palette.secondary == OrexColors.ochre &&
        palette.background == (dark ? OrexColors.darkBg : OrexColors.lightBg);
    // Opaque custom themes have a plain background regardless of their HEX
    // colors. Keep the classic Orex ambient gradient even with glass off.
    final glassEnabled =
        Theme.of(context).extension<OrexGlassAppearance>()?.enabled ?? true;
    if (!glassEnabled && !original) {
      return ColoredBox(color: palette.background, child: child);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: original
            ? (dark ? OrexColors.ambientDark : OrexColors.ambientLight)
            : RadialGradient(
          center: const Alignment(-0.6, -0.8),
          radius: 1.4,
          colors: [
            Color.alphaBlend(
              palette.accent.withValues(alpha: 0.15),
              palette.background,
            ),
            palette.background,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(palette.accent.withValues(alpha: 0.22), 260),
          ),
          Positioned(
            bottom: -100,
            left: -40,
            child: _Blob(palette.secondary.withValues(alpha: 0.16), 300),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob(this.color, this.size);

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}
