import 'dart:ui';

import 'package:flutter/material.dart';

import 'orex_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 18,
    this.opacity = 0.55,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = (tint ?? (isDark ? OrexColors.darkSurface : OrexColors.cream))
        .withValues(alpha: opacity);
    final borderColor =
        (isDark ? OrexColors.ochreLight : OrexColors.copperBright)
            .withValues(alpha: isDark ? 0.18 : 0.28);

    final filter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glassColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.04 : 0.20),
            Colors.transparent,
          ],
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
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
