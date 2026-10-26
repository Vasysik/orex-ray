import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/profiles/xray_json_file.dart';
import '../../shared/theme/orex_builtin_presets.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/theme/simple_theme_profile.dart';
import '../../shared/theme/theme_controller.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import 'live_theme_editor_screen.dart';

/// Compact theme selection with the original Orex styling left intact.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key, required this.theme});
  final ThemeController theme;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  bool _busy = false;
  ThemeController get theme => widget.theme;
  SimpleThemeProfile? get _editing => theme.editingTheme;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка темы: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEditor(SimpleThemeProfile entry) {
    if (!mounted) return;
    theme.startEditing(entry.id);
  }

  void _closeEditor() {
    theme.cancelEditing();
  }

  Future<void> _create() => _run(() async {
    final created = await theme.createTheme(
      theme.selectedTheme == null ? 'Моя тема Orex' : '${theme.selectedTheme!.name} — копия',
    );
    _openEditor(created);
  });

  Future<void> _duplicatePreset(OrexBuiltinPreset preset) => _run(() async {
    await theme.selectBuiltin(preset.id);
    final entry = await theme.createTheme('${preset.title} — копия');
    _openEditor(entry);
  });

  Future<void> _edit(SimpleThemeProfile entry) => _run(() async {
    await theme.selectTheme(entry.id);
    _openEditor(entry);
  });

  Future<void> _import() => _run(() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'OrexRay JSON Theme', extensions: ['json']),
    ]);
    if (file == null) return;
    if (await file.length() > ThemeController.maxThemeJsonBytes) {
      throw const FormatException('Файл темы слишком большой');
    }
    final entry = await theme.importThemeJson(await file.readAsString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортирована тема «${entry.name}»')),
      );
    }
  });

  Future<void> _export(String? id, {String? preset}) => _run(() async {
    final json = preset == null
        ? await theme.exportThemeJson(id!)
        : await theme.exportBuiltinJson(preset);
    final safe = (preset ?? id ?? 'orex').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final saved = await const XrayJsonFileExporter().save(
      content: json,
      suggestedName: 'orexray-theme-$safe.json',
    );
    if (mounted && saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тема экспортирована вместе с маскотом')),
      );
    }
  });

  Future<void> _remove(SimpleThemeProfile entry) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить тему?'),
        content: Text('Тема «${entry.name}» будет удалена. Встроенные темы останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) await theme.deleteTheme(entry.id);
  });


  Widget _themeTileLeading(SimpleThemeProfile entry) {
    final palette = OrexPalette.resolve(
      entry.light ? Brightness.light : Brightness.dark,
      entry.colors,
    );
    final image = entry.mascotPath.isEmpty
        ? const SquirrelMascot(size: 48, compact: true, forceDefault: true)
        : Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: palette.accent.withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              )],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(entry.mascotPath),
              fit: BoxFit.cover,
              cacheWidth: 128,
              errorBuilder: (context, error, stackTrace) =>
                  const SquirrelMascot(size: 48, compact: true, forceDefault: true),
            ),
          );
    if (theme.selectedId != entry.id) return image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
            ),
            child: Icon(Icons.check_rounded, size: 11, color:
              ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
                  ? Colors.white : Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _presetTile(OrexBuiltinPreset preset) => ListTile(
    key: ValueKey('preset-${preset.id}'),
    selected: theme.selectedId == preset.storageId,
    leading: SizedBox.square(
      dimension: 48,
      child: FutureBuilder(
        future: preset.loadMascotPreview(),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return CircleAvatar(
              backgroundColor: preset.accent.withValues(alpha: 0.17),
              child: Icon(Icons.public_rounded, color: preset.accent),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 128),
          );
        },
      ),
    ),
    title: Text(preset.title),
    subtitle: Text(preset.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    onTap: _busy ? null : () => _run(() => theme.selectBuiltin(preset.id)),
    trailing: PopupMenuButton<String>(
      tooltip: 'Действия с темой',
      onSelected: (action) {
        switch (action) {
          case 'copy': _duplicatePreset(preset);
          case 'export': _export(null, preset: preset.id);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'copy', child: Text('Создать редактируемую копию')),
        PopupMenuItem(value: 'export', child: Text('Экспорт JSON + маскот')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: theme,
    builder: (context, _) => ListView(
      // A new scrollable when switching views ensures the editor opens at
      // its header, not at the bottom of the previously scrolled theme list.
      key: ValueKey(_editing == null ? 'theme-list' : 'theme-editor-view'),
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsPageHeader(
          title: 'Интерфейс',
          subtitle: 'Темы, цвета, маскоты и стеклянные панели',
          icon: Icons.palette_outlined,
        ),
        const SizedBox(height: 22),
        if (_editing != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('theme-editor-back'),
              onPressed: _busy ? null : _closeEditor,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Назад к темам'),
            ),
          ),
          const SizedBox(height: 8),
          SimpleThemeEditorScreen(
            key: ValueKey('inline-editor-${_editing!.id}'),
            theme: theme,
            initial: _editing!,
            onClose: _closeEditor,
          ),
        ] else ...[
        SettingsSection(title: 'Стиль', children: [
          SwitchListTile(
            key: const ValueKey('appearance-glass-toggle'),
            secondary: const Icon(Icons.blur_on_rounded),
            title: const Text('Стеклянные панели'),
            subtitle: const Text('Размытие и полупрозрачные поверхности'),
            value: theme.glassEnabled,
            onChanged: theme.setGlassEnabled,
          ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Встроенные темы', children: [
          ListTile(
            key: const ValueKey('theme-default'),
            selected: theme.selectedId == null,
            leading: const SquirrelMascot(size: 48, compact: true, forceDefault: true),
            title: const Text('Классический Orex'),
            subtitle: const Text('Оригинальное оформление и белочка'),
            onTap: _busy ? null : () => _run(() => theme.selectTheme(null)),
          ),
          for (final preset in OrexBuiltinPreset.values) ...[
            const Divider(height: 1),
            _presetTile(preset),
          ],
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Мои темы', children: [
          for (final entry in theme.customThemes) ...[
            ListTile(
              key: ValueKey('theme-${entry.id}'),
              selected: theme.selectedId == entry.id,
              leading: _themeTileLeading(entry),
              title: Text(entry.name),
              subtitle: const Text('Настраиваемые цвета, маскот и стекло'),
              onTap: () => _run(() => theme.selectTheme(entry.id)),
              trailing: PopupMenuButton<String>(
                tooltip: 'Действия с темой',
                onSelected: (action) {
                  switch (action) {
                    case 'edit': _edit(entry);
                    case 'export': _export(entry.id);
                    case 'delete': _remove(entry);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  PopupMenuItem(value: 'export', child: Text('Экспорт JSON + маскот')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить тему')),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            key: const ValueKey('theme-create'),
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Создать собственную тему'),
            subtitle: const Text('Копия текущего оформления'),
            enabled: !_busy, onTap: _create,
          ),
          ListTile(
            key: const ValueKey('theme-import'),
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Импортировать JSON-тему'),
            subtitle: const Text('Цвета, стекло и изображение маскота'),
            enabled: !_busy, onTap: _import,
          ),
        ]),
        ],
      ],
    ),
  );
}
