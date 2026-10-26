import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:orex_ray/shared/theme/orex_builtin_presets.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/theme/orex_palette.dart';
import 'package:orex_ray/shared/theme/simple_theme_profile.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('classic Orex retains exact original Material styling', () {
    final base = OrexTheme.dark;
    final classic = OrexTheme.withColors(Brightness.dark, const {});
    expect(classic.colorScheme, base.colorScheme);
    expect(classic.filledButtonTheme.style?.backgroundColor?.resolve({}),
        base.filledButtonTheme.style?.backgroundColor?.resolve({}));
    expect(classic.iconTheme.color, base.iconTheme.color);
  });

  test('all four built-in preset JSONs embed mascot bytes', () async {
    for (final preset in OrexBuiltinPreset.values) {
      final contents = await rootBundle.loadString(preset.assetPath);
      final parsed = jsonDecode(contents) as Map<String, dynamic>;
      expect(parsed['format'], 'orexray-theme');
      expect(parsed['name'], preset.title);
      final mascot = parsed['mascot'] as String;
      expect(mascot, startsWith('data:image/webp;base64,'));
      expect(base64Decode(mascot.split(';base64,').last), isNotEmpty);
      expect(parsed['colors'], isA<Map>());
    }
  });

  test('create, select, edit and reload themes without loading image assets',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    expect(controller.selectedTheme, isNull);
    expect(controller.glassEnabled, isTrue);

    final created = await controller.createTheme('Первая тема');
    await controller.setColor('accent', const Color(0xFF33CC77));
    await controller.setColor('background', const Color(0xFF131313));
    controller.previewGlass(opacity: 0.35, blur: 12, glow: 0.8);
    await controller.saveGlass();
    await controller.renameTheme(created.id, 'Зелёная');
    final reloaded = await ThemeController.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.selectedTheme?.name, 'Зелёная');
    expect(reloaded.colors['accent'], const Color(0xFF33CC77));
    expect(reloaded.colors['background'], const Color(0xFF131313));
    expect(reloaded.selectedTheme?.glassOpacity, 0.35);
    expect(reloaded.selectedTheme?.glassBlur, 12);
    expect(reloaded.selectedTheme?.glassGlow, 0.8);

    await reloaded.resetColor('accent');
    expect(reloaded.colors.containsKey('accent'), isFalse);
    await reloaded.selectTheme(null);
    expect(reloaded.selectedTheme, isNull);
    expect(reloaded.colors, isEmpty);
    expect(reloaded.mascotPath, isEmpty);
  });

  test('copying classic Orex starts with the same palette and no panel halo',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    final copy = await controller.createTheme('Классический — копия');
    expect(copy.colors, isEmpty);
    expect(copy.mascotPath, isEmpty);
    expect(copy.light, isFalse);
    expect(copy.glassGlow, 0);
    expect(copy.glassOpacity, SimpleThemeProfile.defaultGlassOpacity);
    expect(copy.glassBlur, SimpleThemeProfile.defaultGlassBlur);
    expect(OrexTheme.withColors(Brightness.dark, copy.colors).colorScheme,
        OrexTheme.dark.colorScheme);
  });

  test('untouched old classic copies drop the accidental 22 percent glow',
      () async {
    final classicPalette = OrexPalette.resolve(Brightness.dark, const {});
    final oldCopy = SimpleThemeProfile(
      id: 'user_old_classic',
      name: 'Classic copy',
      colors: {
        for (final role in OrexPalette.roles.keys)
          role: classicPalette.role(role),
      },
      glassGlow: 0.22,
    );
    SharedPreferences.setMockInitialValues({
      'orex_ray_simple_themes_v1': jsonEncode([oldCopy.toStoredJson()]),
      'orex_ray_simple_selected_theme_v1': oldCopy.id,
    });
    final loaded = await ThemeController.load();
    addTearDown(loaded.dispose);
    expect(loaded.selectedTheme?.colors, isEmpty);
    expect(loaded.selectedTheme?.glassGlow, 0);
  });

  test('signed glass halo survives self-contained JSON', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    final copy = await controller.createTheme('Теневой Orex');
    await controller.updateThemeDesign(
      copy.id,
      name: copy.name,
      colors: copy.colors,
      light: copy.light,
      opacity: copy.glassOpacity,
      blur: copy.glassBlur,
      glow: -0.85,
    );
    final json = await controller.exportThemeJson(copy.id);
    expect((jsonDecode(json) as Map)['glass']['glow'], -0.85);
    final imported = await controller.importThemeJson(json);
    expect(imported.glassGlow, -0.85);
    expect(() => SimpleThemeProfile.validateGlass(0.55, 18, -0.86),
        throwsFormatException);
    expect(() => SimpleThemeProfile.validateGlass(0.55, 18, 0.86),
        throwsFormatException);
  });

  test('export/import gives independent themes with JSON palette', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    await controller.createTheme('Нуар');
    await controller.setColor('accent', const Color(0xFFD0D0D0));
    final originalId = controller.selectedId;
    final portable = await controller.exportThemeJson(originalId!);
    final decoded = jsonDecode(portable) as Map<String, dynamic>;
    expect(decoded['format'], 'orexray-theme');
    expect(decoded['version'], 1);
    expect(decoded['mascot'], isNull);
    expect((decoded['colors'] as Map)['accent'], '#ffd0d0d0');
    expect((decoded['glass'] as Map)['opacity'], SimpleThemeProfile.defaultGlassOpacity);
    expect(portable.contains('mascotPath'), isFalse);

    final imported = await controller.importThemeJson(portable);
    expect(imported.id, isNot(originalId));
    expect(controller.themes, hasLength(2));
    expect(controller.selectedId, imported.id);
    expect(controller.colors['accent'], const Color(0xFFD0D0D0));
    expect(controller.selectedTheme?.glassBlur, SimpleThemeProfile.defaultGlassBlur);
    await controller.deleteTheme(originalId);
    expect(controller.themes, hasLength(1));
  });

  test('invalid JSON never changes themes', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    await expectLater(
      controller.importThemeJson('{"format":"unknown","version":1}'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      controller.importThemeJson(jsonEncode({
        'format': 'orexray-theme',
        'version': 1,
        'name': 'Unsafe',
        'colors': {'accent': 'not-a-color'},
        'mascot': null,
      })),
      throwsA(isA<FormatException>()),
    );
    expect(controller.themes, isEmpty);
  });

  test('invalid glass parameters are rejected before importing', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    await expectLater(
      controller.importThemeJson(jsonEncode({
        'format': 'orexray-theme',
        'version': 1,
        'name': 'Invalid',
        'colors': <String, String>{},
        'glass': {'opacity': 8, 'blur': 18, 'glow': 0.2},
      })),
      throwsA(isA<FormatException>()),
    );
    expect(controller.themes, isEmpty);
  });

  test('color parser accepts hex and rejects unknown roles', () {
    expect(
      SimpleThemeProfile.parseColors({'text': '#FFFFFF'})['text'],
      const Color(0xFFFFFFFF),
    );
    expect(
      () => SimpleThemeProfile.parseColors({'not_a_role': '#FFAABBCC'}),
      throwsFormatException,
    );
    expect(OrexPalette.roles, contains('border'));
  });

  test('Soft Lime and Noir use calm, dark palette presets', () async {
    final lime = jsonDecode(await rootBundle.loadString(
      'assets/themes/presets/cabbage.json',
    )) as Map<String, dynamic>;
    final noir = jsonDecode(await rootBundle.loadString(
      'assets/themes/presets/noir.json',
    )) as Map<String, dynamic>;
    expect(lime['light'], isFalse);
    expect((lime['colors'] as Map)['background'], '#FF0E140A');
    expect((lime['colors'] as Map)['surface'], '#FF1C2812');
    expect((lime['colors'] as Map)['accent'], '#FFC9E279');
    expect(noir['name'], 'Серая тема Орешка');
    expect((noir['colors'] as Map)['accent'], '#FF4F8FB8');
    expect((noir['colors'] as Map)['secondary'], '#FF356E97');
    expect((noir['colors'] as Map)['background'], '#FF202020');
    expect((noir['colors'] as Map)['surface'], '#FF2B2B2B');
    expect((noir['glass'] as Map)['enabled'], isFalse);
    // A self-contained preset must still carry its own mascot bytes.
    expect(lime['mascot'], startsWith('data:image/webp;base64,'));
    expect(noir['mascot'], startsWith('data:image/webp;base64,'));
  });

  test('old built-in colors migrate without modifying user copies', () async {
    final oldPreset = SimpleThemeProfile(
      id: 'preset_cabbage',
      name: 'Soft Lime',
      builtin: true,
      light: true,
      colors: const {
        'background': Color(0xFFF0F9D1),
        'accent': Color(0xFF83B83D),
      },
    );
    final userCopy = SimpleThemeProfile(
      id: 'user_copy',
      name: 'My Lime',
      light: true,
      colors: const {'background': Color(0xFFF0F9D1)},
    );
    SharedPreferences.setMockInitialValues({
      'orex_ray_simple_themes_v1': jsonEncode([
        oldPreset.toStoredJson(),
        userCopy.toStoredJson(),
      ]),
      'orex_ray_simple_selected_theme_v1': 'preset_cabbage',
    });
    final controller = await ThemeController.load();
    addTearDown(controller.dispose);
    expect(controller.selectedTheme!.light, isFalse);
    expect(controller.colors['background'], const Color(0xFF0E140A));
    expect(controller.colors['accent'], const Color(0xFFC9E279));
    expect(controller.customThemes.single.colors['background'],
        const Color(0xFFF0F9D1));
  });

  test('live draft is visible globally, cancel discards it, save persists',
      () async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);
    final profile = await theme.createTheme('Test Theme');
    expect(theme.selectedTheme!.glassEnabled, isTrue);
    theme.startEditing(profile.id);
    theme.updateEditing(
      name: 'Unsaved',
      colors: const {'accent': Color(0xFF60CDFF)},
      glassEnabled: false,
      glow: -0.45,
    );
    expect(theme.colors['accent'], const Color(0xFF60CDFF));
    expect(theme.effectiveGlassEnabled, isFalse);
    expect(theme.activeTheme?.glassGlow, -0.45);
    expect(theme.editingThemeId, profile.id);
    expect(theme.selectedTheme!.colors, isEmpty);
    expect(theme.selectedTheme!.name, 'Test Theme');
    final otherInstance = await ThemeController.load();
    addTearDown(otherInstance.dispose);
    expect(otherInstance.selectedTheme!.colors, isEmpty);
    expect(otherInstance.selectedTheme!.glassEnabled, isTrue);

    theme.cancelEditing();
    expect(theme.editingThemeId, isNull);
    expect(theme.colors, isEmpty);
    expect(theme.effectiveGlassEnabled, isTrue);
    await theme.updateThemeDesign(
      profile.id,
      name: 'Saved',
      colors: const {'accent': Color(0xFF60CDFF)},
      light: false,
      glassEnabled: false,
      opacity: 0.55,
      blur: 18,
      glow: -0.45,
    );
    final saved = await ThemeController.load();
    addTearDown(saved.dispose);
    expect(saved.selectedTheme!.name, 'Saved');
    expect(saved.selectedTheme!.glassEnabled, isFalse);
    expect(saved.effectiveGlassEnabled, isFalse);
    expect(saved.colors['accent'], const Color(0xFF60CDFF));
    final exported = jsonDecode(await saved.exportThemeJson(profile.id)) as Map;
    expect((exported['glass'] as Map)['enabled'], isFalse);
  });

  test('gray builtin preset is migrated without changing user copies',
      () async {
    final old = SimpleThemeProfile(
      id: 'preset_noir', name: 'Monochrome Noir', builtin: true,
      colors: const {'background': Color(0xFF050506)},
    );
    final copy = SimpleThemeProfile(
      id: 'user_noir', name: 'My Noir',
      colors: const {'background': Color(0xFF050506)},
    );
    SharedPreferences.setMockInitialValues({
      'orex_ray_simple_themes_v1': jsonEncode([
        old.toStoredJson(), copy.toStoredJson(),
      ]),
      'orex_ray_simple_selected_theme_v1': 'preset_noir',
    });
    final theme = await ThemeController.load();
    addTearDown(theme.dispose);
    expect(theme.selectedTheme!.name, 'Серая тема Орешка');
    expect(theme.colors['accent'], const Color(0xFF4F8FB8));
    expect(theme.colors['secondary'], const Color(0xFF356E97));
    expect(theme.colors['background'], const Color(0xFF202020));
    expect(theme.effectiveGlassEnabled, isFalse);
    expect(theme.customThemes.single.colors['background'],
        const Color(0xFF050506));
  });

  test('custom accents reach Material controls but classic stays unchanged', () {
    const limeAccent = Color(0xFFAACD81);
    final themed = OrexTheme.withColors(Brightness.dark,
        const {'accent': limeAccent, 'border': Color(0xFF516C45)});
    expect(themed.colorScheme.primary, limeAccent);
    expect(themed.listTileTheme.iconColor, limeAccent);
    expect(themed.chipTheme.selectedColor,
        limeAccent.withValues(alpha: 0.20));
    expect(themed.colorScheme.outline, const Color(0xFF516C45));

    final classic = OrexTheme.withColors(Brightness.dark, const {});
    expect(classic.colorScheme.primary, OrexColors.copper);
    expect(classic.filledButtonTheme.style?.backgroundColor?.resolve({}),
        OrexTheme.dark.filledButtonTheme.style?.backgroundColor?.resolve({}));
  });

}
