import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../platform/windows/windows_elevation_controller.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../home/tunnel_controller.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.appVersion,
    required this.tunnel,
  });

  final OrexAppVersion appVersion;
  final TunnelController tunnel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsPageHeader(
          title: 'О приложении',
          subtitle: 'OrexRay — Xray-клиент для Android и Windows',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 22),
        const Center(
          child: SquirrelMascot(size: 128, caption: 'Белочка защищает маршрут'),
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'Версия',
          children: [
            ListTile(
              leading: const Icon(Icons.apps_rounded, color: OrexColors.copper),
              title: const Text('OrexRay'),
              subtitle: Text(appVersion.settingsSubtitle),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: OrexColors.copper),
              title: const Text('Скопировать информацию'),
              subtitle: const Text('Для баг-репорта и диагностики'),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: 'OrexRay ${appVersion.label}'),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Информация скопирована')),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Движок',
          subtitle: 'Версия и обслуживание сетевого движка.',
          children: [
            const ListTile(
              leading: Icon(Icons.hub_rounded, color: OrexColors.copper),
              title: Text('Xray Core'),
              subtitle: Text('VLESS · REALITY · TLS · TUN · SOCKS5 · HTTP'),
            ),
            if (Platform.isWindows) ...[
              const Divider(height: 1),
              _XrayCoreMaintenanceTile(tunnel: tunnel),
            ],
          ],
        ),
      ],
    );
  }
}

class _XrayCoreMaintenanceTile extends StatefulWidget {
  const _XrayCoreMaintenanceTile({required this.tunnel});

  final TunnelController tunnel;

  @override
  State<_XrayCoreMaintenanceTile> createState() =>
      _XrayCoreMaintenanceTileState();
}

class _XrayCoreMaintenanceTileState extends State<_XrayCoreMaintenanceTile> {
  bool _repairing = false;
  double? _progress;

  Future<void> _reinstall() async {
    if (_repairing) return;
    if (!widget.tunnel.canReinstallXrayCore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала отключи активное соединение.')),
      );
      return;
    }

    if (await WindowsElevationController.isProtectedInstall() &&
        !await WindowsElevationController.isElevated()) {
      if (!mounted) return;
      final restart = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Нужны права администратора'),
              content: const Text(
                'Xray Core установлен в Program Files. OrexRay перезапустится '
                'с правами администратора; после перезапуска снова открой '
                '«О приложении» и нажми «Переустановить Xray Core».',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Перезапустить'),
                ),
              ],
            ),
          ) ??
          false;
      if (!restart) return;
      await WindowsElevationController.restartElevated();
      return;
    }

    setState(() {
      _repairing = true;
      _progress = null;
    });
    try {
      await widget.tunnel.reinstallXrayCore(
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value.clamp(0.0, 1.0).toDouble());
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xray Core переустановлен и проверен.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переустановить Xray Core: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _repairing = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.tunnel,
      builder: (context, _) {
        final canRepair = widget.tunnel.canReinstallXrayCore;
        return ListTile(
          leading: const Icon(
            Icons.system_update_alt_rounded,
            color: OrexColors.copper,
          ),
          title: const Text('Переустановить Xray Core'),
          subtitle: Text(
            _repairing
                ? _progress == null
                    ? 'Подготавливаем восстановление…'
                    : 'Загрузка · ${(_progress! * 100).round()}%'
                : canRepair
                    ? 'Восстанавливает xray.exe, wintun.dll и встроенные '
                        'GeoData из закреплённого архива с проверкой SHA-256.'
                    : 'Отключи активное соединение для обслуживания движка.',
          ),
          trailing: OutlinedButton.icon(
            onPressed: _repairing || !canRepair ? null : _reinstall,
            icon: _repairing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_circle_outlined),
            label: const Text('Переустановить'),
          ),
        );
      },
    );
  }
}
