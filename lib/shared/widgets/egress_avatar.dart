import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../core/egress/egress_identity.dart';
import '../theme/orex_theme.dart';
import '../theme/orex_palette.dart';

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
    final palette = OrexPalette.of(context);
    final original = palette.accent == OrexColors.copper &&
        palette.secondary == OrexColors.ochre;
    final foreground = original
        ? OrexColors.cream
        : (ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
            ? Colors.white
            : Colors.black);
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
              gradient: selected
                  ? (original
                      ? OrexColors.copperGradient
                      : LinearGradient(colors: [palette.accent, palette.secondary]))
                  : null,
              color: selected ? null : palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(size * 0.31),
            ),
            child: value == null
                ? Icon(
                    selected ? Icons.check_rounded : fallbackIcon,
                    color: selected ? foreground : palette.accent,
                    size: size * 0.5,
                  )
                : _CountryFlag(
                    countryCode: value.countryCode,
                    size: size,
                    fallbackColor:
                        selected ? foreground : palette.accent,
                  ),
          ),
          if (value?.warp == true)
            Positioned(
              right: -3,
              bottom: -3,
              child: Semantics(
                label: 'Cloudflare WARP',
                child: Container(
                  width: radius,
                  height: radius,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.accent, width: 1.5),
                  ),
                  child: Icon(
                    SimpleIcons.cloudflare,
                    color: SimpleIconColors.cloudflare,
                    size: size * 0.19,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountryFlag extends StatelessWidget {
  const _CountryFlag({
    required this.countryCode,
    required this.size,
    required this.fallbackColor,
  });

  final String countryCode;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final normalized = countryCode.trim().toUpperCase();
    if (FlagCode.fromCountryCode(normalized) == null) {
      return Text(
        normalized,
        style: TextStyle(
          color: fallbackColor,
          fontSize: size * 0.26,
          fontWeight: FontWeight.w900,
          letterSpacing: size * 0.012,
          height: 1,
        ),
      );
    }

    return CountryFlag.fromCountryCode(
      normalized,
      theme: ImageTheme(
        width: size * 0.75,
        height: size * 0.51,
        shape: RoundedRectangle(size * 0.075),
      ),
    );
  }
}
