import 'package:flutter/material.dart';

import '../theme/orex_theme.dart';

/// Фирменная белочка OrexRay: глобальная сеть, скорлупа-защита и наш клиент.
class SquirrelMascot extends StatelessWidget {
  const SquirrelMascot({
    super.key,
    this.size = 88,
    this.caption,
    this.compact = false,
  });

  final double size;
  final String? caption;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
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
              color: OrexColors.copper.withValues(alpha: 0.28),
              blurRadius: compact ? 18 : 34,
              offset: Offset(0, compact ? 6 : 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/images/orexray_logo.png',
          fit: BoxFit.cover,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );

    if (caption == null) return mascot;
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
