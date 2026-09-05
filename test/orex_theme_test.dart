import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';

void main() {
  test('uses the shared Orex Messenger palette for primary tokens', () {
    expect(OrexColors.walnut, const Color(0xFF8B5A2B));
    expect(OrexColors.walnutDeep, const Color(0xFF5E3A1A));
    expect(OrexColors.copper, const Color(0xFFD47939));
    expect(OrexColors.copperBright, const Color(0xFFEE8D3F));
    expect(OrexColors.copperDeep, const Color(0xFF854132));
    expect(OrexColors.cream, const Color(0xFFFCFAFA));
    expect(OrexColors.online, const Color(0xFF8FB36A));
    expect(OrexColors.danger, const Color(0xFFB36A6A));
    expect(OrexColors.dangerStrong, OrexColors.danger);
    expect(OrexColors.copperGradient.colors, [
      OrexColors.copperBright,
      OrexColors.copperDeep,
    ]);
  });
}
