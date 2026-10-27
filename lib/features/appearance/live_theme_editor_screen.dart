import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/orex_palette.dart';
import '../../shared/theme/simple_theme_profile.dart';
import '../../shared/theme/theme_controller.dart';
import '../../shared/widgets/settings_section.dart';

/// Inline controls for a transient app-wide theme draft. Navigating away does
/// not dispose the draft: the entire application uses it until Save / Cancel.
class SimpleThemeEditorScreen extends StatefulWidget {
  const SimpleThemeEditorScreen({
    super.key,
    required this.theme,
    required this.initial,
    required this.onClose,
  });

  final ThemeController theme;
  final SimpleThemeProfile initial;
  final VoidCallback onClose;

  @override
  State<SimpleThemeEditorScreen> createState() => _SimpleThemeEditorScreenState();
}

class _SimpleThemeEditorScreenState extends State<SimpleThemeEditorScreen> {
  late final TextEditingController _name;
  late final Map<String, TextEditingController> _colors;
  late final Map<String, Color> _validColors;
  late bool _light;
  late bool _glassEnabled;
  late double _opacity;
  late double _blur;
  late double _glow;
  Uint8List? _selectedImage;
  bool _resetMascot = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = widget.theme.activeTheme?.id == widget.initial.id
        ? widget.theme.activeTheme!
        : widget.initial;
    _name = TextEditingController(text: current.name);
    final palette = OrexPalette.resolve(
      current.light ? Brightness.light : Brightness.dark,
      current.colors,
    );
    _validColors = {
      for (final role in OrexPalette.roles.keys) role: palette.role(role),
    };
    _colors = {
      for (final entry in _validColors.entries)
        entry.key: TextEditingController(text: _hex(entry.value)),
    };
    _light = current.light;
    _glassEnabled = current.glassEnabled;
    _opacity = current.glassOpacity;
    _blur = current.glassBlur;
    _glow = current.glassGlow;
    _selectedImage = widget.theme.mascotBytes;
    _resetMascot = widget.theme.draftMascotReset;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _colors.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  Color? _parseColor(String text) {
    var hex = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return null;
    }
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Map<String, Color> _overrides() {
    final original = OrexPalette.resolve(
      _light ? Brightness.light : Brightness.dark,
      const {},
    );
    return {
      for (final entry in _validColors.entries)
        if (entry.value.toARGB32() != original.role(entry.key).toARGB32())
          entry.key: entry.value,
    };
  }

  void _applyLive() {
    widget.theme.updateEditing(
      name: _name.text,
      colors: _overrides(),
      light: _light,
      glassEnabled: _glassEnabled,
      opacity: _opacity,
      blur: _blur,
      glow: _glow,
    );
  }

  void _changeColor(String role, String text) {
    final parsed = _parseColor(text);
    if (parsed != null) {
      _validColors[role] = parsed;
      _applyLive();
    }
    // The text field can temporarily contain an incomplete HEX number.
    // Keep displaying its last valid value until the input is complete.
    setState(() {});
  }

  Future<void> _chooseColor(String role) async {
    final original = _validColors[role]!;
    var picker = HSVColor.fromColor(original);
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void change(HSVColor color) {
            setDialogState(() => picker = color);
            // The actual app changes even while dragging inside the picker.
            _validColors[role] = color.toColor();
            _applyLive();
          }
          return AlertDialog(
            title: Text(OrexPalette.roles[role]!),
            content: SizedBox(
              width: 350,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LayoutBuilder(builder: (context, box) {
                  const height = 170.0;
                  final width = box.maxWidth;
                  void sample(Offset position) {
                    change(picker.withSaturation(
                      (position.dx / width).clamp(0.0, 1.0).toDouble(),
                    ).withValue(
                      (1 - position.dy / height).clamp(0.0, 1.0).toDouble(),
                    ));
                  }
                  return GestureDetector(
                    onPanDown: (details) => sample(details.localPosition),
                    onPanUpdate: (details) => sample(details.localPosition),
                    onTapDown: (details) => sample(details.localPosition),
                    child: SizedBox(
                      height: height,
                      child: Stack(children: [
                        Positioned.fill(child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HSVColor.fromAHSV(1, picker.hue, 1, 1).toColor(),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.white, Colors.transparent],
                              ),
                            ),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black],
                                ),
                              ),
                            ),
                          ),
                        )),
                        Positioned(
                          left: (picker.saturation * width - 7).clamp(0.0, width - 14).toDouble(),
                          top: ((1 - picker.value) * height - 7).clamp(0.0, height - 14).toDouble(),
                          child: IgnorePointer(child: Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(
                                color: Colors.black54, blurRadius: 3,
                              )],
                            ),
                          )),
                        ),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Оттенок'),
                ),
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    gradient: const LinearGradient(colors: [
                      Colors.red, Colors.yellow, Colors.green,
                      Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                    ]),
                  ),
                ),
                Slider(
                  value: picker.hue,
                  min: 0, max: 360,
                  onChanged: (hue) => change(picker.withHue(hue)),
                ),
                Row(children: [
                  const Text('Непрозрачность'),
                  Expanded(child: Slider(
                    value: picker.alpha,
                    onChanged: (alpha) => change(picker.withAlpha(alpha)),
                  )),
                ]),
                Row(children: [
                  Container(width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: picker.toColor(),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    )),
                  const SizedBox(width: 12),
                  Text(_hex(picker.toColor())),
                ]),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, picker.toColor()),
                child: const Text('Применить'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (result == null) {
      _validColors[role] = original;
      _applyLive();
      return;
    }
    _colors[role]!.text = _hex(result);
    _changeColor(role, _colors[role]!.text);
  }

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
      setState(() {
        _selectedImage = bytes;
        _resetMascot = false;
      });
      widget.theme.updateEditing(mascotBytes: bytes);
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
    for (final role in OrexPalette.roles.keys) {
      if (_parseColor(_colors[role]!.text) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Неверный HEX: ${OrexPalette.roles[role]}')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.theme.updateThemeDesign(
        widget.initial.id,
        name: _name.text,
        colors: _overrides(),
        light: _light,
        glassEnabled: _glassEnabled,
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
          onChanged: (value) {
            setState(() => onChange(value));
            _applyLive();
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 740),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('Изменения сразу видны во всём OrexRay. Можно перейти '
              'в другие разделы и вернуться сюда. «Назад к темам» отменяет '
              'несохранённые изменения.'),
        ),
        const SizedBox(height: 12),
        SettingsSection(title: 'Общее', children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              maxLength: 80,
              onChanged: (_) => _applyLive(),
              decoration: const InputDecoration(labelText: 'Название темы'),
            ),
          ),
          SwitchListTile(
            title: const Text('Светлое оформление'),
            subtitle: const Text('Использовать светлые элементы интерфейса'),
            value: _light,
            onChanged: (value) {
              setState(() => _light = value);
              _applyLive();
            },
          ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Палитра', children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final role in OrexPalette.roles.keys)
                SizedBox(width: 224, child: TextField(
                  key: ValueKey('theme-color-$role'),
                  controller: _colors[role],
                  onChanged: (text) => _changeColor(role, text),
                  decoration: InputDecoration(
                    labelText: OrexPalette.roles[role],
                    errorText: _parseColor(_colors[role]!.text) == null
                        ? 'HEX: #RRGGBB или #AARRGGBB'
                        : null,
                    prefixIcon: IconButton(
                      tooltip: 'Выбрать цвет из палитры',
                      onPressed: () => _chooseColor(role),
                      icon: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _validColors[role],
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                )),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Стекло', children: [
          SwitchListTile(
            key: const ValueKey('theme-glass-enabled'),
            title: const Text('Использовать стекло в этой теме'),
            subtitle: const Text('Выключает размытие, прозрачность и свечение'),
            value: _glassEnabled,
            onChanged: (enabled) {
              setState(() => _glassEnabled = enabled);
              _applyLive();
            },
          ),
          if (_glassEnabled) ...[
            _slider('Прозрачность панелей', 1 - _opacity, 0.05, 0.85,
              '${((1 - _opacity) * 100).round()}%',
              (value) => _opacity = 1 - value, divisions: 16),
            _slider('Размытие', _blur, 0, 36, '${_blur.round()} px',
              (value) => _blur = value, divisions: 36),
            _slider('Затенение / свечение', _glow, -0.85, 0.85,
              '${(_glow * 100).round() > 0 ? '+' : ''}${(_glow * 100).round()}%',
              (value) => _glow = value, divisions: 34),
          ],
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Маскот', children: [
          ListTile(
            key: const ValueKey('theme-mascot-picker'),
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Выбрать изображение'),
            subtitle: const Text('PNG, JPEG или WebP до 6 МБ'),
            onTap: _chooseMascot,
          ),
          if (_selectedImage != null ||
              (!_resetMascot && widget.initial.mascotPath.isNotEmpty))
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Вернуть стандартную белочку'),
              onTap: () {
                setState(() {
                  _resetMascot = true;
                  _selectedImage = null;
                });
                widget.theme.updateEditing(resetMascot: true);
              },
            ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          OutlinedButton(
            onPressed: _saving ? null : widget.onClose,
            child: const Text('Отменить'),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Сохранить тему'),
          )),
        ]),
      ]),
    ));
  }
}
