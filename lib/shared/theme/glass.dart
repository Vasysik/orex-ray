import 'dart:ui';

import 'package:flutter/material.dart';

import 'orex_theme.dart';

/// One app-wide switch that applies to panels, including modal routes.
class OrexGlassAppearance extends ThemeExtension<OrexGlassAppearance> {
  const OrexGlassAppearance({this.enabled = true});

  final bool enabled;

  @override
  OrexGlassAppearance copyWith({bool? enabled}) =>
      OrexGlassAppearance(enabled: enabled ?? this.enabled);

  @override
  OrexGlassAppearance lerp(ThemeExtension<OrexGlassAppearance>? other, double t) {
    if (other is! OrexGlassAppearance) return this;
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
    final isDark = theme.brightness == Brightness.dark;
    final glassEnabled =
        theme.extension<OrexGlassAppearance>()?.enabled ?? true;
    final baseColor = isDark ? OrexColors.darkSurface : OrexColors.lightSurface;
    final flatColor = tint == null
        ? baseColor
        : Color.alphaBlend(tint!.withValues(alpha: 0.14), baseColor);
    final glassColor =
        (tint ?? (isDark ? OrexColors.darkSurface : OrexColors.cream))
            .withValues(alpha: opacity);
    final borderColor =
        (isDark ? OrexColors.ochreLight : OrexColors.copperBright)
            .withValues(alpha: isDark ? 0.18 : 0.28);

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
    if (!glassEnabled) return panel;
    final filter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final grouped = BackdropGroup.of(context) != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: grouped
          ? BackdropFilter.grouped(filter: filter, child: panel)
          : BackdropFilter(filter: filter, child: panel),
    );
  }
}

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDark ? OrexColors.ambientDark : OrexColors.ambientLight,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(OrexColors.copper.withValues(alpha: 0.22), 260),
          ),
          Positioned(
            bottom: -100,
            left: -40,
            child: _Blob(OrexColors.ochre.withValues(alpha: 0.16), 300),
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
