import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/orex_palette.dart';
import '../theme/orex_theme.dart';

/// Provides an optional mascot image to existing SquirrelMascot widgets.
class OrexMascotAppearance extends ThemeExtension<OrexMascotAppearance> {
  const OrexMascotAppearance({this.filePath = ''});

  final String filePath;

  @override
  OrexMascotAppearance copyWith({String? filePath}) =>
      OrexMascotAppearance(filePath: filePath ?? this.filePath);

  @override
  OrexMascotAppearance lerp(
    ThemeExtension<OrexMascotAppearance>? other,
    double t,
  ) => other is OrexMascotAppearance && t >= 0.5 ? other : this;
}

/// Фирменная белочка OrexRay: глобальная сеть, скорлупа-защита и наш клиент.
class SquirrelMascot extends StatelessWidget {
  const SquirrelMascot({
    super.key,
    this.size = 88,
    this.caption,
    this.compact = false,
    this.forceDefault = false,
  });

  final double size;
  final String? caption;
  final bool compact;
  /// Always display the original Orex logo, even if another theme is active.
  final bool forceDefault;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    final selectedPath = forceDefault
        ? ''
        : (Theme.of(context)
            .extension<OrexMascotAppearance>()?.filePath ?? '');
    final palette = OrexPalette.of(context);
    final decodeWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 768)
        .toInt();
    final mascot = Semantics(
      image: true,
      label: 'Белочка OrexRay в защищённой ореховой скорлупе',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              // The classic icon keeps its original copper halo regardless of
              // which custom palette is currently active.
              color: (selectedPath.isEmpty
                      ? OrexColors.copper
                      : palette.accent)
                  .withValues(alpha: 0.28),
              blurRadius: compact ? 18 : 34,
              offset: Offset(0, compact ? 6 : 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: selectedPath.isEmpty
            ? Image.asset(
                'assets/images/orexray_logo.png',
                fit: BoxFit.cover,
                cacheWidth: decodeWidth,
                filterQuality: FilterQuality.medium,
              )
            : Image.file(
                File(selectedPath),
                fit: BoxFit.cover,
                cacheWidth: decodeWidth,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stack) => Image.asset(
                  'assets/images/orexray_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
      ),
    );

    if (caption == null) {
      return mascot;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mascot,
        const SizedBox(height: 12),
        Text(
          caption!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
