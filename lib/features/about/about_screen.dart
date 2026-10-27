import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/update/orexray_updates.dart';
import '../../shared/widgets/orexray_update_dialog.dart';
import '../../platform/windows/windows_elevation_controller.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/orex_confirm_dialog.dart';
import '../../shared/widgets/orex_notice.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../home/tunnel_controller.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.appVersion,
    required this.tunnel,
    this.updates,
  });

  final OrexAppVersion appVersion;
  final TunnelController tunnel;
  final OrexRayUpdates? updates;

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
              leading: Icon(Icons.apps_rounded, color: OrexPalette.of(context).accent),
              title: const Text('OrexRay'),
              subtitle: Text(appVersion.settingsSubtitle),
            ),
            if (updates != null) ...[
              const Divider(height: 1),
              AnimatedBuilder(
                animation: updates!,
                builder: (context, _) {
                  final model = updates!;
                  return ListTile(
                    key: const ValueKey('orexray-check-updates'),
                    leading: Icon(Icons.system_update_rounded, color: OrexPalette.of(context).accent),
                    title: Text(model.available != null ? 'Установить обновление' : 'Проверить обновления'),
                    subtitle: Text(switch (model.state) {
                      OrexRayUpdateState.checking => 'Проверяем GitHub Releases…',
                      OrexRayUpdateState.available => 'Доступна ${model.available!.tag}',
                      OrexRayUpdateState.upToDate => 'Установлена последняя версия',
                      OrexRayUpdateState.error => model.error ?? 'Проверка не удалась',
                      _ => 'Источник: GitHub Releases',
                    }),
                    onTap: model.state == OrexRayUpdateState.checking ? null : () async {
                      if (model.available == null) await model.check();
                      if (!context.mounted) return;
                      if (model.available != null) {
                        await showOrexRayUpdateDialog(context, model);
                      } else {
                        OrexNotice.show(context, SnackBar(content: Text(
                          model.error ?? 'Новых версий нет',
                        )));
                      }
                    },
                    trailing: model.state == OrexRayUpdateState.checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right_rounded),
                  );
                },
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.copy_rounded, color: OrexPalette.of(context).accent),
              title: const Text('Скопировать информацию'),
              subtitle: const Text('Для баг-репорта и диагностики'),
              mouseCursor: SystemMouseCursors.click,
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: 'OrexRay ${appVersion.label}'),
                );
                if (context.mounted) {
                  OrexNotice.show(
                    context,
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
             ListTile(
              leading: Icon(Icons.hub_rounded, color: OrexPalette.of(context).accent),
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
      OrexNotice.show(
        context,
        const SnackBar(content: Text('Сначала отключи активное соединение.')),
      );
      return;
    }

    if (await WindowsElevationController.isProtectedInstall() &&
        !await WindowsElevationController.isElevated()) {
      if (!mounted) return;
      final restart = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => const OrexConfirmDialog(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Нужны права администратора',
              content: Text(
                'Xray Core установлен в Program Files. OrexRay перезапустится '
                'с правами администратора; после перезапуска снова открой '
                '«О приложении» и нажми «Переустановить Xray Core».',
              ),
              confirmLabel: 'Перезапустить',
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
      OrexNotice.show(
        context,
        const SnackBar(content: Text('Xray Core переустановлен и проверен.')),
      );
    } catch (error) {
      if (!mounted) return;
      OrexNotice.show(
        context,
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
          leading: Icon(Icons.system_update_alt_rounded,
            color: OrexPalette.of(context).accent,
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
