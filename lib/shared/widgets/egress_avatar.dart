import 'package:flutter/material.dart';

import '../../core/egress/egress_identity.dart';
import '../theme/orex_theme.dart';

class EgressAvatar extends StatelessWidget {
  const EgressAvatar({
    super.key,
    required this.identity,
    this.fallbackIcon = Icons.public_rounded,
    this.selected = false,
    this.size = 48,
  });

  final EgressIdentity? identity;
  final IconData fallbackIcon;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = identity;
    final radius = size * 0.31;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? OrexColors.copperGradient : null,
              color: selected ? null : OrexColors.copper.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(size * 0.31),
            ),
            child: value == null
                ? Icon(
                    selected ? Icons.check_rounded : fallbackIcon,
                    color: selected ? OrexColors.cream : OrexColors.copper,
                    size: size * 0.5,
                  )
                : Text(
                    value.flagEmoji,
                    style: TextStyle(fontSize: size * 0.52, height: 1),
                  ),
          ),
          if (value?.warp == true)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: radius,
                height: radius,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: OrexColors.copper, width: 1.5),
                ),
                child: Text(
                  'W',
                  style: TextStyle(
                    color: OrexColors.copper,
                    fontSize: size * 0.19,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
