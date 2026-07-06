import 'package:flutter/material.dart';

import '../../core/geodata/geodata_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';

class GeoDataScreen extends StatelessWidget {
  const GeoDataScreen({super.key, required this.controller});

  final GeoDataController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SettingsPageHeader(
            title: 'GeoData',
            subtitle: 'GeoIP и GeoSite для правил маршрутизации Xray',
            icon: Icons.travel_explore_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Состояние',
            children: [
              for (var index = 0; index < controller.assets.length; index++) ...[
                _AssetTile(asset: controller.assets[index]),
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
            title: 'Обновления',
            subtitle: 'Файлы проверяются по SHA-256 перед заменой.',
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
                          if (value != null) {
                            controller.setUpdateIntervalHours(value);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.error != null)
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
          if (controller.message != null) ...[
            GlassPanel(
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: Text(controller.message!),
            ),
            const SizedBox(height: 12),
          ],
          if (controller.updating) ...[
            LinearProgressIndicator(value: controller.progress),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: controller.updating ? null : controller.updateNow,
            icon: const Icon(Icons.download_for_offline_rounded),
            label: Text(controller.updating ? 'Обновляем…' : 'Обновить GeoData сейчас'),
          ),
          const SizedBox(height: 8),
          Text(
            'Обновлённые файлы используются при следующем запуске Xray.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});

  final GeoAssetStatus asset;

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
      trailing: Text(asset.fileName),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
}
