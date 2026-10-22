import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/features/appearance/appearance_screen.dart';
import 'package:orex_ray/shared/theme/glass.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opaque surfaces do not use blur when glass is off',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark.copyWith(
          extensions: [const OrexGlassAppearance(enabled: false)],
        ),
        home: const Scaffold(body: GlassPanel(child: Text('OrexRay'))),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final surface = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassPanel),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color!.a, 1);
    expect(decoration.gradient, isNull);
  });

  testWidgets('custom glass opacity and glow affect the panel', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark.copyWith(
        extensions: [const OrexGlassAppearance(
          enabled: true,
          opacity: 0.35,
          blur: 8,
          glow: 0.75,
        )],
      ),
      home: const Scaffold(body: GlassPanel(child: Text('OrexRay'))),
    ));
    final panel = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassPanel),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = panel.decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(0.35, 0.001));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('negative glow casts a dark shadow; zero keeps classic unglowed',
      (tester) async {
    Future<Color?> shadowColor(double glow) async {
      await tester.pumpWidget(MaterialApp(
        theme: OrexTheme.dark.copyWith(
          extensions: [OrexGlassAppearance(glow: glow)],
        ),
        home: const Scaffold(body: GlassPanel(child: Text('Panel'))),
      ));
      // Theme extensions animate between successive pumpWidget calls.
      // Sample only the settled appearance, not the previous halo.
      await tester.pumpAndSettle();
      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(GlassPanel),
          matching: find.byType(DecoratedBox),
        ),
      );
      for (final widget in decorated) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration &&
            decoration.boxShadow != null &&
            decoration.boxShadow!.isNotEmpty) {
          return decoration.boxShadow!.first.color;
        }
      }
      return null;
    }

    final dark = await shadowColor(-0.85);
    expect(dark, isNotNull);
    final darkColor = dark!;
    expect(darkColor.r, 0);
    expect(darkColor.g, 0);
    expect(darkColor.b, 0);
    final neutral = await shadowColor(0);
    expect(neutral, isNull);
    final bright = await shadowColor(0.85);
    expect(bright, isNotNull);
    expect(bright, isNot(equals(darkColor)));
  });

  testWidgets('glass switch persists and defaults to on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);
    expect(theme.glassEnabled, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(body: AppearanceScreen(theme: theme)),
      ),
    );
    final switchTile = find.byKey(const ValueKey('appearance-glass-toggle'));
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    await tester.tap(switchTile);
    await tester.pumpAndSettle();
    expect(theme.glassEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('orex_ray_glass_enabled'), isFalse);
  });
}
