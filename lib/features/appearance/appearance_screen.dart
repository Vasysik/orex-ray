import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/profiles/xray_json_file.dart';
import '../../shared/l10n/orex_l10n.dart';
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
          SnackBar(content: Text('Ошибка темы: {}'.trf([error]))),
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
      theme.selectedTheme == null
          ? 'Моя тема Orex'.tr
          : '{} — копия'.trf([theme.selectedTheme!.name]),
    );
    _openEditor(created);
  });

  Future<void> _duplicatePreset(OrexBuiltinPreset preset) => _run(() async {
    await theme.selectBuiltin(preset.id);
    final entry =
        await theme.createTheme('{} — копия'.trf([theme.selectedTheme!.name]));
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
      throw FormatException('Файл темы слишком большой'.tr);
    }
    final entry = await theme.importThemeJson(await file.readAsString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортирована тема «{}»'.trf([entry.name]))),
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
        SnackBar(content: Text('Тема экспортирована вместе с маскотом'.tr)),
      );
    }
  });

  Future<void> _remove(SimpleThemeProfile entry) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Удалить тему?'.tr),
        content: Text(
          'Тема «{}» будет удалена. Встроенные темы останутся.'.tr
              .trf([entry.name]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text('Отмена'.tr)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text('Удалить'.tr)),
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

  Widget _presetTile(OrexBuiltinPreset preset) =>
      FutureBuilder<OrexBuiltinPresetPreview?>(
    future: preset.loadPreview(),
    builder: (context, snapshot) {
      final preview = snapshot.data;
      final accent = preview?.accent ?? OrexPalette.of(context).accent;
      final bytes = preview?.mascotBytes;
      final failed = snapshot.connectionState == ConnectionState.done &&
          preview == null;
      return ListTile(
        key: ValueKey('preset-${preset.id}'),
        selected: theme.selectedId == preset.storageId,
        leading: SizedBox.square(
          dimension: 48,
          child: bytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 128),
                )
              : snapshot.hasData
                  // A preset without its own mascot uses the default squirrel.
                  ? const SquirrelMascot(size: 48, compact: true, forceDefault: true)
                  : CircleAvatar(
                      backgroundColor: accent.withValues(alpha: 0.17),
                      child: Icon(Icons.public_rounded, color: accent),
                    ),
        ),
        // Built-in preset texts are app data, so they follow the app
        // language; user-created themes keep whatever name they entered.
        title: Text(preview == null ? 'Загрузка темы…'.tr : preview.name.tr),
        subtitle: Text(
          preview == null
              ? (failed ? 'Не удалось прочитать JSON пресета'.tr : 'Загрузка описания…'.tr)
              : preview.description.tr,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: _busy || failed ? null : () => _run(() => theme.selectBuiltin(preset.id)),
        trailing: PopupMenuButton<String>(
          enabled: !_busy && !failed,
          tooltip: 'Действия с темой'.tr,
          onSelected: (action) {
            switch (action) {
              case 'copy': _duplicatePreset(preset);
              case 'export': _export(null, preset: preset.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'copy', child: Text('Создать редактируемую копию'.tr)),
            PopupMenuItem(value: 'export', child: Text('Экспорт JSON + маскот'.tr)),
          ],
        ),
      );
    },
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
        SettingsPageHeader(
          title: 'Интерфейс'.tr,
          subtitle: 'Темы, цвета, маскоты и стеклянные панели'.tr,
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
              label: Text('Назад к темам'.tr),
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
        SettingsSection(title: 'Стиль'.tr, children: [
          AnimatedBuilder(
            animation: OrexL10n.instance,
            builder: (context, _) {
              final languageNames = <String, String>{
                'system': 'Как в системе'.tr,
                'ru': 'Русский'.tr,
                'en': 'English',
              };
              return ListTile(
                key: const ValueKey('appearance-language'),
                leading: Icon(Icons.translate_rounded),
                title: Text('Язык'.tr),
                subtitle: Text(
                  'Применяется ко всему приложению'.tr,
                ),
                trailing: DropdownButton<String>(
                  value: OrexL10n.instance.language,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value != null) OrexL10n.instance.setLanguage(value);
                  },
                  items: [
                    for (final entry in languageNames.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                ),
              );
            },
          ),
          SwitchListTile(
            key: const ValueKey('appearance-glass-toggle'),
            secondary: const Icon(Icons.blur_on_rounded),
            title: Text('Стеклянные панели'.tr),
            subtitle: Text('Размытие и полупрозрачные поверхности'.tr),
            value: theme.glassEnabled,
            onChanged: theme.setGlassEnabled,
          ),
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Встроенные темы'.tr, children: [
          for (var i = 0; i < OrexBuiltinPreset.values.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _presetTile(OrexBuiltinPreset.values[i]),
          ],
        ]),
        const SizedBox(height: 16),
        SettingsSection(title: 'Мои темы'.tr, children: [
          for (final entry in theme.customThemes) ...[
            ListTile(
              key: ValueKey('theme-${entry.id}'),
              selected: theme.selectedId == entry.id,
              leading: _themeTileLeading(entry),
              title: Text(entry.name),
              subtitle: Text('Настраиваемые цвета, маскот и стекло'.tr),
              onTap: () => _run(() => theme.selectTheme(entry.id)),
              trailing: PopupMenuButton<String>(
                tooltip: 'Действия с темой'.tr,
                onSelected: (action) {
                  switch (action) {
                    case 'edit': _edit(entry);
                    case 'export': _export(entry.id);
                    case 'delete': _remove(entry);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('Редактировать'.tr)),
                  PopupMenuItem(value: 'export', child: Text('Экспорт JSON + маскот'.tr)),
                  PopupMenuItem(value: 'delete', child: Text('Удалить тему'.tr)),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            key: const ValueKey('theme-create'),
            leading: const Icon(Icons.add_circle_outline),
            title: Text('Создать собственную тему'.tr),
            subtitle: Text('Копия текущего оформления'.tr),
            enabled: !_busy, onTap: _create,
          ),
          ListTile(
            key: const ValueKey('theme-import'),
            leading: const Icon(Icons.file_open_outlined),
            title: Text('Импортировать JSON-тему'.tr),
            subtitle: Text('Цвета, стекло и изображение маскота'.tr),
            enabled: !_busy, onTap: _import,
          ),
        ]),
        ],
      ],
    ),
  );
}
