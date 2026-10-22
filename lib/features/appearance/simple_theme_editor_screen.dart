import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/orex_palette.dart';
import '../../shared/theme/simple_theme_profile.dart';
import '../../shared/theme/theme_controller.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/widgets/squirrel_mascot.dart';

/// Restored preview-first editor layout, with only the requested simple controls.
class SimpleThemeEditorScreen extends StatefulWidget {
  const SimpleThemeEditorScreen({
    super.key,
    required this.theme,
    required this.initial,
    required this.onClose,
  });

  final ThemeController theme;
  final SimpleThemeProfile initial;
  /// Close the inline editor without pushing or popping a Navigator route.
  final VoidCallback onClose;

  @override
  State<SimpleThemeEditorScreen> createState() => _SimpleThemeEditorScreenState();
}

class _SimpleThemeEditorScreenState extends State<SimpleThemeEditorScreen> {
  late final TextEditingController _name;
  late final Map<String, TextEditingController> _colors;
  late bool _light;
  late double _opacity;
  late double _blur;
  late double _glow;
  Uint8List? _selectedImage;
  bool _resetMascot = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = widget.initial;
    _name = TextEditingController(text: current.name);
    final fallback = OrexPalette.resolve(
      current.light ? Brightness.light : Brightness.dark,
      current.colors,
    );
    _colors = {
      for (final role in OrexPalette.roles.keys)
        role: TextEditingController(text: _hex(fallback.role(role))),
    };
    _light = current.light;
    _opacity = current.glassOpacity;
    _blur = current.glassBlur;
    _glow = current.glassGlow;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final field in _colors.values) { field.dispose(); }
    super.dispose();
  }

  String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  Color? _parseColor(String text) {
    var hex = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) return null;
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Color _color(String role) => _parseColor(_colors[role]!.text) ?? Colors.grey;

  Future<void> _chooseMascot() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Изображение', extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ]);
      if (file == null) return;
      if (await file.length() > ThemeController.maxMascotBytes) {
        throw const FormatException('Маскот больше 6 МБ');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() { _selectedImage = bytes; _resetMascot = false; });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить картинку: $error')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final colors = <String, Color>{};
    final classicPalette = OrexPalette.resolve(
      _light ? Brightness.light : Brightness.dark,
      const {},
    );
    for (final role in OrexPalette.roles.keys) {
      final color = _parseColor(_colors[role]!.text);
      if (color == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Неверный HEX: ${OrexPalette.roles[role]}')),
        );
        return;
      }
      // Keep original Orex theme data untouched when the user saves a copy
      // without changing its palette. Only store actual color overrides.
      if (color.toARGB32() != classicPalette.role(role).toARGB32()) {
        colors[role] = color;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.theme.updateThemeDesign(
        widget.initial.id,
        name: _name.text,
        colors: colors,
        light: _light,
        opacity: _opacity,
        blur: _blur,
        glow: _glow,
      );
      if (_selectedImage != null) {
        await widget.theme.setMascot(_selectedImage!);
      } else if (_resetMascot) {
        await widget.theme.resetMascot();
      }
      if (mounted) widget.onClose();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _previewMascot() {
    final bytes = _selectedImage;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(bytes, fit: BoxFit.cover),
      );
    }
    if (!_resetMascot && widget.initial.mascotPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(File(widget.initial.mascotPath), fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SquirrelMascot(size: 76, forceDefault: true)),
      );
    }
    return const SquirrelMascot(size: 76, forceDefault: true);
  }

  Widget _slider(String title, double value, double min, double max,
      String display, ValueChanged<double> onChange, {int? divisions}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title)),
          Text(display, style: Theme.of(context).textTheme.bodySmall),
        ]),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min, max: max, divisions: divisions, label: display,
          onChanged: (v) => setState(() => onChange(v)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _color('accent');
    final background = _color('background');
    final surface = _color('surface');
    final textColor = _color('text');
    // Embedded in the AppearanceScreen scroll area: no Scaffold, route or
    // nested ListView. The caller keeps its sidebar and settings header.
    return Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // The large preview and grouped compact editors are taken from
              // the earlier editor layout, not the temporary plain ListTiles.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.7)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    SizedBox.square(dimension: 76, child: _previewMascot()),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name.text.isEmpty ? 'Новая тема' : _name.text,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontSize: 19,
                              fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Предпросмотр карточки',
                            style: TextStyle(color: textColor)),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Кнопка',
                            style: TextStyle(color: background)),
                        ),
                      ],
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              SettingsSection(title: 'Общее', children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _name,
                    maxLength: 80,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Название темы'),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Светлое оформление'),
                  subtitle: const Text('Использовать светлые элементы интерфейса'),
                  value: _light,
                  onChanged: (value) => setState(() => _light = value),
                ),
              ]),
              const SizedBox(height: 16),
              SettingsSection(title: 'Палитра (HEX)', children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final role in OrexPalette.roles.keys)
                      SizedBox(width: 210, child: TextField(
                        key: ValueKey('theme-color-$role'),
                        controller: _colors[role],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: OrexPalette.roles[role],
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(10),
                            child: DecoratedBox(decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _color(role),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                            )),
                          ),
                        ),
                      )),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              SettingsSection(title: 'Стекло', children: [
                _slider('Прозрачность панелей', 1 - _opacity, 0.05, 0.85,
                    '${((1 - _opacity) * 100).round()}%',
                    (v) => _opacity = 1 - v, divisions: 16),
                _slider('Размытие', _blur, 0, 36, '${_blur.round()} px',
                    (v) => _blur = v, divisions: 36),
                _slider('Затенение / свечение', _glow, -0.85, 0.85,
                    '${(_glow * 100).round() > 0 ? '+' : ''}${(_glow * 100).round()}%',
                    (v) => _glow = v, divisions: 34),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('−85% — тёмная тень, 0% — как у классического Orex, '
                      '+85% — цветное свечение.'),
                ),
              ]),
              const SizedBox(height: 16),
              SettingsSection(title: 'Маскот', children: [
                ListTile(
                  key: const ValueKey('theme-mascot-picker'),
                  leading: const Icon(Icons.upload_file_rounded),
                  title: const Text('Выбрать изображение'),
                  subtitle: const Text('PNG, JPEG или WebP до 6 МБ; картинка включена в JSON'),
                  onTap: _chooseMascot,
                ),
                if (_selectedImage != null ||
                    (!_resetMascot && widget.initial.mascotPath.isNotEmpty))
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Вернуть стандартную белочку'),
                    onTap: () => setState(() {
                      _resetMascot = true; _selectedImage = null;
                    }),
                  ),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Сохранить тему'),
              ),
            ]),
          ));
  }
}
