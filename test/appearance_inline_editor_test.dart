import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/features/appearance/appearance_screen.dart';
import 'package:orex_ray/features/appearance/live_theme_editor_screen.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
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
}
