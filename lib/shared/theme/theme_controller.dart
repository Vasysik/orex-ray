import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'orex_palette.dart';
import 'orex_builtin_presets.dart';
import 'simple_theme_profile.dart';

/// Saved theme definitions are lightweight (name, colors, private mascot
/// path). Exported JSON embeds the actual mascot bytes and is self-contained.
/// No image or preset asset I/O happens in load(), avoiding widget-test stalls.
class ThemeController extends ChangeNotifier {
  ThemeController._(
    this._mode,
    this._glassEnabled,
    this._selectedId,
    List<SimpleThemeProfile> themes,
  ) : _themes = themes;

  static const _modeKey = 'orex_ray_theme_mode';
  static const _glassKey = 'orex_ray_glass_enabled';
  static const _themesKey = 'orex_ray_simple_themes_v1';
  static const _selectedKey = 'orex_ray_simple_selected_theme_v1';
  static const maxMascotBytes = 6 * 1024 * 1024;
  static const maxThemeJsonBytes = 9 * 1024 * 1024;

  ThemeMode _mode;
  ThemeMode get mode => _mode;
  bool _glassEnabled;
  bool get glassEnabled => _glassEnabled;
  String? _selectedId;
  String? get selectedId => _selectedId;
  final List<SimpleThemeProfile> _themes;
  List<SimpleThemeProfile> get themes => List.unmodifiable(_themes);
  List<SimpleThemeProfile> get customThemes => List.unmodifiable(_themes.where((t) => !t.builtin));

  SimpleThemeProfile? get selectedTheme {
    for (final item in _themes) {
      if (item.id == _selectedId) {
        return item;
      }
    }
    return null;
  }

  Map<String, Color> get colors => selectedTheme?.colors ?? const {};
  String get mascotPath => selectedTheme?.mascotPath ?? '';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = switch (prefs.getString(_modeKey)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final profiles = <SimpleThemeProfile>[];
    final raw = prefs.getString(_themesKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          for (final entry in data) {
            try {
              if (entry is Map) {
                profiles.add(SimpleThemeProfile.fromStoredJson(
                  Map<String, dynamic>.from(entry),
                ));
              }
            } on Object {
              // Ignore a broken entry without discarding other saved themes.
            }
          }
        }
      } on Object {
        // A damaged preference must not prevent app startup.
      }
    }
    // Upgrade previously selected built-in presets without loading megabytes
    // of Base64 mascot JSON during application startup. Custom copies are
    // deliberately untouched; their palettes belong to their owners.
    for (var i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      // Older editor versions stored every untouched classic color and a
      // 22% halo on newly created themes. Upgrade only untouched classic
      // copies; deliberate user palettes and glass settings stay unchanged.
      final classicPalette = OrexPalette.resolve(Brightness.dark, const {});
      if (!profile.builtin &&
          !profile.light &&
          profile.mascotPath.isEmpty &&
          profile.glassOpacity == SimpleThemeProfile.defaultGlassOpacity &&
          profile.glassBlur == SimpleThemeProfile.defaultGlassBlur &&
          profile.glassGlow == 0.22 &&
          profile.colors.entries.every(
            (entry) => classicPalette.role(entry.key).toARGB32() ==
                entry.value.toARGB32(),
          )) {
        profiles[i] = profile.copyWith(
          colors: const {},
          glassGlow: SimpleThemeProfile.defaultGlassGlow,
        );
        continue;
      }
      if (profile.id == 'preset_cabbage' &&
          profile.colors['background'] == const Color(0xFFF0F9D1)) {
        profiles[i] = profile.copyWith(
          colors: {
            'accent': const Color(0xFFAACD81),
            'secondary': const Color(0xFF789C5D),
            'background': const Color(0xFF101A0E),
            'surface': const Color(0xFF23351B),
            'text': const Color(0xFFF0F6E8),
            'mutedText': const Color(0xFFB1C5A1),
            'border': const Color(0xFF516C45),
          },
          light: false,
          glassOpacity: 0.58,
          glassGlow: 0.09,
        );
      } else if (profile.id == 'preset_noir' &&
          profile.colors['background'] == const Color(0xFF090A0B)) {
        profiles[i] = profile.copyWith(
          colors: {
            'accent': const Color(0xFFAAAAAA),
            'secondary': const Color(0xFF686868),
            'background': const Color(0xFF050506),
            'surface': const Color(0xFF0E0F10),
            'text': const Color(0xFFE8E8E8),
            'mutedText': const Color(0xFF9D9D9D),
            'border': const Color(0xFF323334),
          },
          glassOpacity: 0.67,
          glassGlow: 0.06,
        );
      }
    }
    final selected = prefs.getString(_selectedKey);
    return ThemeController._(
      mode,
      prefs.getBool(_glassKey) ?? true,
      profiles.any((item) => item.id == selected) ? selected : null,
      profiles,
    );
  }

  String _nextId() => 'user_${DateTime.now().microsecondsSinceEpoch}_${_themes.length}';

  Future<void> _saveThemes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themesKey,
      jsonEncode(_themes.map((item) => item.toStoredJson()).toList()),
    );
    if (_selectedId == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, _selectedId!);
    }
    notifyListeners();
  }

  Future<SimpleThemeProfile> createTheme(String name) async {
    if (name.trim().isEmpty) {
      throw const FormatException('Введите имя темы');
    }
    final source = selectedTheme;
    final theme = SimpleThemeProfile(
      id: _nextId(),
      name: name.trim(),
      colors: source?.colors ?? const {},
      mascotPath: source?.mascotPath ?? '',
      builtin: false,
      light: source?.light ?? false,
      glassOpacity: source?.glassOpacity ?? SimpleThemeProfile.defaultGlassOpacity,
      glassBlur: source?.glassBlur ?? SimpleThemeProfile.defaultGlassBlur,
      glassGlow: source?.glassGlow ?? SimpleThemeProfile.defaultGlassGlow,
    );
    _themes.add(theme);
    _selectedId = theme.id;
    await _saveThemes();
    return theme;
  }

  Future<void> selectTheme(String? id) async {
    if (id != null && !_themes.any((item) => item.id == id)) {
      throw const FormatException('Тема не найдена');
    }
    if (_selectedId == id) {
      return;
    }
    _selectedId = id;
    await _saveThemes();
  }

  /// Presets are portable, self-contained JSON files. Their large mascot
  /// is decoded only when this preset is first selected, never on startup.
  Future<void> selectBuiltin(String id) async {
    final preset = OrexBuiltinPreset.values.where((p) => p.id == id).firstOrNull;
    if (preset == null) throw const FormatException('Встроенная тема не найдена');
    // Always read the JSON on selection: users may have an older cached
    // built-in theme saved before this release updated its palette.
    final existingIndex = _themes.indexWhere(
      (theme) => theme.id == preset.storageId,
    );
    final contents = await rootBundle.loadString(preset.assetPath);
    if (utf8.encode(contents).length > maxThemeJsonBytes) {
      throw const FormatException('Встроенная тема слишком большая');
    }
    final data = jsonDecode(contents);
    if (data is! Map || data['format'] != 'orexray-theme' ||
        data['version'] != 1 || data['name'] != preset.title) {
      throw const FormatException('Неверный формат встроенной темы');
    }
    final colors = SimpleThemeProfile.parseColors(data['colors']);
    final (opacity, blur, glow) = SimpleThemeProfile.parseGlass(data['glass']);
    final encoded = data['mascot'];
    if (encoded is! String || !encoded.startsWith('data:image/') ||
        !encoded.contains(';base64,')) {
      throw const FormatException('Отсутствует маскот встроенной темы');
    }
    final parts = encoded.split(';base64,');
    if (parts.length != 2 || parts.last.length > maxMascotBytes * 4 ~/ 3 + 8) {
      throw const FormatException('Неверные данные маскота');
    }
    final bytes = base64Decode(parts.last);
    final mime = _mimeType(bytes);
    if (parts.first != 'data:$mime') {
      throw const FormatException('Неверный тип маскота');
    }
    final previousPath = existingIndex >= 0
        ? _themes[existingIndex].mascotPath
        : '';
    final path = previousPath.isNotEmpty && await File(previousPath).exists()
        ? previousPath
        : await _storeMascot(bytes);
    final entry = SimpleThemeProfile(
      id: preset.storageId,
      name: preset.title,
      colors: colors,
      mascotPath: path,
      builtin: true,
      light: data['light'] == true,
      glassOpacity: opacity,
      glassBlur: blur,
      glassGlow: glow,
    );
    if (existingIndex >= 0) {
      _themes[existingIndex] = entry;
    } else {
      _themes.add(entry);
    }
    _selectedId = entry.id;
    await _saveThemes();
  }

  Future<void> renameTheme(String id, String name) async {
    if (_themes.any((t) => t.id == id && t.builtin)) {
      throw const FormatException('Встроенную тему можно только копировать');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Введите имя темы');
    }
    _updateTheme(id, (item) => item.copyWith(name: name.trim()));
    await _saveThemes();
  }

  Future<void> deleteTheme(String id) async {
    if (_themes.any((t) => t.id == id && t.builtin)) {
      throw const FormatException('Встроенную тему нельзя удалить');
    }
    _themes.removeWhere((item) => item.id == id);
    if (_selectedId == id) {
      _selectedId = null;
    }
    await _saveThemes();
  }

  void _updateTheme(
    String id,
    SimpleThemeProfile Function(SimpleThemeProfile) update,
  ) {
    final index = _themes.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw const FormatException('Сначала создайте тему');
    }
    if (_themes[index].builtin) {
      throw const FormatException('Сначала создайте копию встроенной темы');
    }
    _themes[index] = update(_themes[index]);
  }

  /// One atomic preference update from the editor, after validating fields.
  Future<void> updateThemeDesign(
    String id, {
    required String name,
    required Map<String, Color> colors,
    required bool light,
    required double opacity,
    required double blur,
    required double glow,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw const FormatException('Название темы должно содержать до 80 символов');
    }
    for (final role in colors.keys) {
      if (!OrexPalette.roles.containsKey(role)) {
        throw const FormatException('Неизвестный цвет темы');
      }
    }
    SimpleThemeProfile.validateGlass(opacity, blur, glow);
    _updateTheme(id, (theme) => theme.copyWith(
      name: name.trim(),
      colors: Map.of(colors),
      light: light,
      glassOpacity: opacity,
      glassBlur: blur,
      glassGlow: glow,
    ));
    await _saveThemes();
  }

  Future<String> exportBuiltinJson(String presetId) async {
    final preset = OrexBuiltinPreset.values.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) throw const FormatException('Встроенная тема не найдена');
    return rootBundle.loadString(preset.assetPath);
  }

  Future<void> setColor(String role, Color color) async {
    if (!OrexPalette.roles.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Unknown color role');
    }
    final current = selectedTheme;
    if (current == null) {
      throw const FormatException('Сначала создайте тему');
    }
    _updateTheme(current.id, (item) => item.copyWith(
      colors: {...item.colors, role: color},
    ));
    await _saveThemes();
  }

  Future<void> resetColor(String role) async {
    final current = selectedTheme;
    if (current == null) {
      return;
    }
    final next = Map<String, Color>.from(current.colors)..remove(role);
    _updateTheme(current.id, (item) => item.copyWith(colors: next));
    await _saveThemes();
  }

  /// Preview changes without I/O during slider drag; save once on drag end.
  void previewGlass({
    double? opacity,
    double? blur,
    double? glow,
  }) {
    final current = selectedTheme;
    if (current == null) {
      return;
    }
    final nextOpacity = opacity ?? current.glassOpacity;
    final nextBlur = blur ?? current.glassBlur;
    final nextGlow = glow ?? current.glassGlow;
    SimpleThemeProfile.validateGlass(nextOpacity, nextBlur, nextGlow);
    _updateTheme(current.id, (item) => item.copyWith(
      glassOpacity: nextOpacity,
      glassBlur: nextBlur,
      glassGlow: nextGlow,
    ));
    notifyListeners();
  }

  Future<void> saveGlass() => _saveThemes();

  static String _mimeType(Uint8List bytes) {
    if (bytes.length > maxMascotBytes || bytes.length < 4) {
      throw const FormatException('Картинка должна быть до 6 МБ');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47 &&
        bytes[4] == 0x0d && bytes[5] == 0x0a) {
      return 'image/png';
    }
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    throw const FormatException('Поддерживаются PNG, JPEG и WebP');
  }

  Future<void> setMascot(Uint8List bytes) async {
    final current = selectedTheme;
    if (current == null) {
      throw const FormatException('Сначала создайте тему');
    }
    final path = await _storeMascot(bytes);
    _updateTheme(current.id, (item) => item.copyWith(mascotPath: path));
    await _saveThemes();
  }

  Future<String> _storeMascot(Uint8List bytes) async {
    final mime = _mimeType(bytes);
    final dir = await getApplicationSupportDirectory();
    final extension = mime == 'image/png' ? 'png' : mime == 'image/jpeg' ? 'jpg' : 'webp';
    final path = '${dir.path}${Platform.pathSeparator}'
        'orexray_theme_${DateTime.now().microsecondsSinceEpoch}.$extension';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> resetMascot() async {
    final current = selectedTheme;
    if (current == null) {
      return;
    }
    _updateTheme(current.id, (item) => item.copyWith(mascotPath: ''));
    await _saveThemes();
  }

  /// Portable, self-contained theme JSON. The local private file path is never
  /// exposed; the image is embedded in the exported document.
  Future<String> exportThemeJson(String id) async {
    final theme = _themes.where((item) => item.id == id).firstOrNull;
    if (theme == null) {
      throw const FormatException('Тема не найдена');
    }
    String? mascot;
    if (theme.mascotPath.isNotEmpty) {
      final bytes = await File(theme.mascotPath).readAsBytes();
      final mime = _mimeType(bytes);
      mascot = 'data:$mime;base64,${base64Encode(bytes)}';
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'orexray-theme',
      'version': 1,
      'name': theme.name,
      'colors': theme.toStoredJson()['colors'],
      'light': theme.light,
      'glass': theme.glassJson,
      'mascot': mascot,
    });
  }

  Future<SimpleThemeProfile> importThemeJson(String text) async {
    if (utf8.encode(text).length > maxThemeJsonBytes) {
      throw const FormatException('Файл темы слишком большой');
    }
    final raw = jsonDecode(text);
    if (raw is! Map || raw['format'] != 'orexray-theme' || raw['version'] != 1) {
      throw const FormatException('Это не JSON-тема OrexRay');
    }
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty || name.length > 80) {
      throw const FormatException('Некорректное название темы');
    }
    final colors = SimpleThemeProfile.parseColors(raw['colors']);
    final (opacity, blur, glow) = SimpleThemeProfile.parseGlass(raw['glass']);
    String path = '';
    final mascot = raw['mascot'];
    if (mascot != null) {
      if (mascot is! String ||
          !mascot.startsWith('data:image/') ||
          !mascot.contains(';base64,')) {
        throw const FormatException('Неверное изображение темы');
      }
      final parts = mascot.split(';base64,');
      if (parts.length != 2 || parts.last.length > (maxMascotBytes * 4 ~/ 3 + 8)) {
        throw const FormatException('Слишком большое изображение');
      }
      final bytes = base64Decode(parts.last);
      final mime = _mimeType(bytes);
      if (parts.first != 'data:$mime') {
        throw const FormatException('Тип изображения не совпадает с содержимым');
      }
      path = await _storeMascot(bytes);
    }
    final imported = SimpleThemeProfile(
      id: _nextId(),
      name: name.trim(),
      colors: colors,
      mascotPath: path,
      light: raw['light'] == true,
      glassOpacity: opacity,
      glassBlur: blur,
      glassGlow: glow,
    );
    _themes.add(imported);
    _selectedId = imported.id;
    await _saveThemes();
    return imported;
  }

  Future<void> setGlassEnabled(bool enabled) async {
    if (_glassEnabled == enabled) {
      return;
    }
    _glassEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_glassKey, enabled);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }
}
