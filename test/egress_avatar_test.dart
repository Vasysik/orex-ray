import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/egress_identity.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/widgets/egress_avatar.dart';
import 'package:simple_icons/simple_icons.dart';

void main() {
  testWidgets('egress avatar renders an image flag for the ISO country code',
      (tester) async {
    final identity = EgressIdentity(
      countryCode: 'NL',
      warp: false,
      checkedAt: DateTime.utc(2026, 9, 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: EgressAvatar(identity: identity),
        ),
      ),
    );

    expect(find.byType(CountryFlag), findsOneWidget);
    expect(find.text('NL'), findsNothing);
    expect(find.byIcon(Icons.public_rounded), findsNothing);
    expect(find.byIcon(SimpleIcons.cloudflare), findsNothing);
  });

  testWidgets('WARP egress uses the Cloudflare brand badge', (tester) async {
    final identity = EgressIdentity(
      countryCode: 'DE',
      warp: true,
      checkedAt: DateTime.utc(2026, 9, 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: EgressAvatar(identity: identity),
        ),
      ),
    );

    expect(find.byType(CountryFlag), findsOneWidget);
    expect(find.text('DE'), findsNothing);
    expect(find.byIcon(SimpleIcons.cloudflare), findsOneWidget);
  });

  testWidgets('unknown country code keeps a readable text fallback',
      (tester) async {
    final identity = EgressIdentity(
      countryCode: 'ZZ',
      warp: false,
      checkedAt: DateTime.utc(2026, 9, 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: EgressAvatar(identity: identity),
        ),
      ),
    );

    expect(find.byType(CountryFlag), findsNothing);
    expect(find.text('ZZ'), findsOneWidget);
  });
}
