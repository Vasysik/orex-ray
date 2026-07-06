import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/geodata/geodata_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';

class GeoDataScreen extends StatelessWidget {
  const GeoDataScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  final GeoDataController controller;
  final ConnectionSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, settings]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SettingsPageHeader(
            title: 'GeoData',
            subtitle: 'GeoIP и GeoSite для настоящих правил маршрутизации Xray',
            icon: Icons.travel_explore_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Состояние',
            subtitle: 'Можно обновить официальную сборку или подставить свои .dat-файлы.',
            children: [
              for (var index = 0; index < controller.assets.length; index++) ...[
                _AssetTile(
                  asset: controller.assets[index],
                  importing: controller.updating,
                  onImport: () => _importAsset(
                    context,
                    controller.assets[index].fileName,
                  ),
                ),
                if (index != controller.assets.length - 1)
                  const Divider(height: 1),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded, color: OrexColors.copper),
                title: const Text('Каталог данных'),
                subtitle: Text(
                  controller.directoryPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Маршрутизация по GeoData',
            subtitle: 'Правила применяются сверху вниз при следующем подключении.',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.alt_route_rounded, color: OrexColors.copper),
                title: const Text('Использовать GeoData в маршрутах'),
                subtitle: const Text(
                  'Включает правила geoip:… и geosite:… в Xray-конфиг',
                ),
                value: settings.geoRoutingEnabled,
                onChanged: settings.setGeoRoutingEnabled,
              ),
              const Divider(height: 1),
              _RuleTile(
                icon: Icons.block_rounded,
                title: 'Блокировать',
                value: settings.geoBlockRulesText,
                example: 'geosite:category-ads-all',
                enabled: settings.geoRoutingEnabled,
                onEdit: () => _editRules(
                  context,
                  title: 'Блокировать',
                  current: settings.geoBlockRulesText,
                  hint: 'geosite:category-ads-all',
                  onSave: settings.setGeoBlockRules,
                ),
              ),
              const Divider(height: 1),
              _RuleTile(
                icon: Icons.call_split_rounded,
                title: 'Напрямую',
                value: settings.geoDirectRulesText,
                example: 'geoip:private, geosite:ru',
                enabled: settings.geoRoutingEnabled,
                onEdit: () => _editRules(
                  context,
                  title: 'Напрямую',
                  current: settings.geoDirectRulesText,
                  hint: 'geoip:private, geosite:ru',
                  onSave: settings.setGeoDirectRules,
                ),
              ),
              const Divider(height: 1),
              _RuleTile(
                icon: Icons.shield_rounded,
                title: 'Через прокси',
                value: settings.geoProxyRulesText,
                example: 'geosite:google, geoip:telegram',
                enabled: settings.geoRoutingEnabled,
                onEdit: () => _editRules(
                  context,
                  title: 'Через прокси',
                  current: settings.geoProxyRulesText,
                  hint: 'geosite:google, geoip:telegram',
                  onSave: settings.setGeoProxyRules,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Обновления',
            subtitle: 'Скачанные файлы проверяются по SHA-256 перед заменой.',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.sync_rounded, color: OrexColors.copper),
                title: const Text('Автоматически проверять обновления'),
                subtitle: Text(
                  controller.lastCheckedAt == null
                      ? 'Ещё не проверялось'
                      : 'Последняя проверка: ${_formatDate(controller.lastCheckedAt!)}',
                ),
                value: controller.autoUpdate,
                onChanged: controller.setAutoUpdate,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule_rounded, color: OrexColors.copper),
                title: const Text('Интервал проверки'),
                trailing: DropdownButton<int>(
                  value: controller.updateIntervalHours,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 12, child: Text('12 часов')),
                    DropdownMenuItem(value: 24, child: Text('1 день')),
                    DropdownMenuItem(value: 72, child: Text('3 дня')),
                    DropdownMenuItem(value: 168, child: Text('7 дней')),
                  ],
                  onChanged: controller.autoUpdate
                      ? (value) {
                          if (value != null) controller.setUpdateIntervalHours(value);
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.error != null) ...[
            GlassPanel(
              borderRadius: 18,
              tint: OrexColors.danger,
              opacity: 0.14,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: OrexColors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text(controller.error!)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (controller.message != null) ...[
            GlassPanel(
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: Text(controller.message!),
            ),
            const SizedBox(height: 12),
          ],
          if (controller.updating) ...[
            LinearProgressIndicator(
              value: controller.progress <= 0 ? null : controller.progress,
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: controller.updating ? null : controller.updateNow,
            icon: const Icon(Icons.download_for_offline_rounded),
            label: Text(controller.updating ? 'Работаем с GeoData…' : 'Обновить GeoData сейчас'),
          ),
          const SizedBox(height: 8),
          Text(
            'Xray перечитывает GeoData при следующем старте соединения.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _importAsset(BuildContext context, String targetFileName) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Xray GeoData', extensions: ['dat']),
      ],
    );
    if (file == null) return;
    await controller.importCustomAsset(targetFileName, file);
    if (!context.mounted || controller.error != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$targetFileName импортирован')),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.importing,
    required this.onImport,
  });

  final GeoAssetStatus asset;
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        asset.installed ? Icons.check_circle_rounded : Icons.cloud_download_outlined,
        color: asset.installed ? OrexColors.online : OrexColors.copper,
      ),
      title: Text(asset.name),
      subtitle: Text(
        asset.installed
            ? '${_formatBytes(asset.sizeBytes)} · ${_formatDate(asset.modifiedAt!)}'
            : 'Не установлен',
      ),
      trailing: IconButton(
        tooltip: 'Импортировать свой ${asset.fileName}',
        onPressed: importing ? null : onImport,
        icon: const Icon(Icons.file_open_rounded),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.example,
    required this.enabled,
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final String value;
  final String example;
  final bool enabled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final shown = value.trim().isEmpty ? 'Пример: $example' : value;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? OrexColors.copper : null),
      title: Text(title),
      subtitle: Text(shown, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: enabled ? onEdit : null,
    );
  }
}

Future<void> _editRules(
  BuildContext context, {
  required String title,
  required String current,
  required String hint,
  required Future<void> Function(String value) onSave,
}) async {
  final controller = TextEditingController(text: current);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: hint,
              helperText: 'Разделяй правила запятыми, пробелами или переносами строк',
              errorText: error,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await onSave(controller.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on FormatException catch (e) {
                setState(() => error = e.message.toString());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
