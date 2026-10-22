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
