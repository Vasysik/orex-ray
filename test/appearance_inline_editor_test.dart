import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/features/appearance/appearance_screen.dart';
import 'package:orex_ray/features/appearance/live_theme_editor_screen.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/theme/glass.dart';
import 'package:orex_ray/shared/theme/orex_palette.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creating and editing a theme stays inside Interface page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: Scaffold(body: AppearanceScreen(theme: theme)),
    ));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('theme-create')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('theme-create')));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleThemeEditorScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-editor-back')), findsOneWidget);
    expect(theme.selectedTheme?.glassGlow, 0);

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(3));
    expect(sliders.last.min, -0.85);
    expect(sliders.last.max, 0.85);

    // The editor is taller than the 800x600 test viewport. Its Save button
    // is at the bottom of the *outer* Interface ListView, not yet on screen.
    // Jump the page scroll position to its bottom before tapping.
    final pageScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(AppearanceScreen),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(pageScroll.position.maxScrollExtent, greaterThan(0));
    pageScroll.position.jumpTo(pageScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Сохранить тему');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(theme.selectedTheme?.colors, isEmpty);
    expect(theme.selectedTheme?.glassGlow, 0);
    expect(find.byType(SimpleThemeEditorScreen), findsNothing);
  });


  test('unsaved edits remain live but are never persisted and can be cancelled',
      () async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);
    final created = await theme.createTheme('Черновик');

    theme.startEditing(created.id);
    theme.updateEditing(
      name: 'Временное имя',
      colors: {'accent': const Color(0xFF456789)},
      glassEnabled: false,
      glow: -0.45,
    );
    expect(theme.editingThemeId, created.id);
    expect(theme.activeTheme?.name, 'Временное имя');
    expect(theme.colors['accent'], const Color(0xFF456789));
    expect(theme.effectiveGlassEnabled, isFalse);
    expect(theme.selectedTheme?.name, 'Черновик');
    expect(theme.selectedTheme?.colors, isEmpty);

    // A different screen can use the same controller while the draft is open.
    // Loading from preferences must never see that unsaved draft.
    final disk = await ThemeController.load();
    addTearDown(disk.dispose);
    expect(disk.selectedTheme?.name, 'Черновик');
    expect(disk.colors, isEmpty);

    theme.cancelEditing();
    expect(theme.editingThemeId, isNull);
    expect(theme.colors, isEmpty);
    expect(theme.selectedTheme?.name, 'Черновик');
    expect(theme.effectiveGlassEnabled, isTrue);
  });

  test('saved palette and per-theme glass setting survive restart', () async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);
    final created = await theme.createTheme('Серая');
    theme.startEditing(created.id);
    theme.updateEditing(
      name: 'Моя серая',
      colors: {'accent': const Color(0xFF4F8FB8)},
      glassEnabled: false,
      opacity: 0.9,
      blur: 0,
      glow: -0.2,
    );
    await theme.updateThemeDesign(
      created.id,
      name: 'Моя серая',
      colors: {'accent': const Color(0xFF4F8FB8)},
      light: false,
      glassEnabled: false,
      opacity: 0.9,
      blur: 0,
      glow: -0.2,
    );
    theme.cancelEditing();

    final restored = await ThemeController.load();
    addTearDown(restored.dispose);
    expect(restored.selectedTheme?.name, 'Моя серая');
    expect(restored.colors['accent'], const Color(0xFF4F8FB8));
    expect(restored.selectedTheme?.glassEnabled, isFalse);
    expect(restored.effectiveGlassEnabled, isFalse);
    expect(restored.selectedTheme?.glassGlow, -0.2);
  });

  testWidgets('flat custom background follows glass flag, not preset colors',
      (tester) async {
    const background = Color(0xFF24272D);
    const palette = <String, Color>{
      'background': background,
      'surface': Color(0xFF32353A),
      'accent': Color(0xFF547FA8),
    };

    Future<void> pumpTheme({required bool glassEnabled}) async {
      final themed = OrexTheme.withColors(Brightness.dark, palette);
      await tester.pumpWidget(MaterialApp(
        theme: themed.copyWith(extensions: [
          OrexPalette.resolve(Brightness.dark, palette),
          OrexGlassAppearance(enabled: glassEnabled),
        ]),
        home: const Scaffold(
          body: AmbientBackground(child: SizedBox.expand()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final matchingFlatBackground = find.descendant(
      of: find.byType(AmbientBackground),
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == background,
      ),
    );
    await pumpTheme(glassEnabled: false);
    expect(matchingFlatBackground, findsOneWidget);
    await pumpTheme(glassEnabled: true);
    expect(matchingFlatBackground, findsNothing);
  });
}
