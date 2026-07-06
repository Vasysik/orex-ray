import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';
import '../home/tunnel_controller.dart';

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.tunnel,
    required this.settings,
  });

  final TunnelController tunnel;
  final ConnectionSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([tunnel, settings]),
      builder: (context, _) {
        final locked = !tunnel.canChangeMode;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SettingsPageHeader(
              title: 'Подключение',
              subtitle: 'Режим работы и локальные точки входа OrexRay',
              icon: Icons.route_rounded,
            ),
            const SizedBox(height: 22),
            SettingsSection(
              title: 'Режим',
              subtitle: locked
                  ? 'Сначала отключи OrexRay, чтобы сменить режим.'
                  : 'Выбери, какой трафик должен проходить через Xray.',
              children: [
                RadioGroup<ConnectionMode>(
                  groupValue: tunnel.mode,
                  onChanged: (mode) {
                    if (mode != null && tunnel.canChangeMode) {
                      tunnel.setMode(mode);
                    }
                  },
                  child: Column(
                    children: [
                      for (final mode in tunnel.supportedModes)
                        RadioListTile<ConnectionMode>(
                          value: mode,
                          enabled: !locked,
                          secondary: Icon(
                            _modeIcon(mode),
                            color: OrexColors.copper,
                          ),
                          title: Text(mode.title),
                          subtitle: Text(mode.description),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              title: 'Локальный прокси',
              subtitle: 'Эти порты используются и режимом системного прокси Windows.',
              children: [
                ListTile(
                  leading: const Icon(Icons.cable_rounded, color: OrexColors.copper),
                  title: const Text('SOCKS5'),
                  subtitle: Text('${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.socksPort}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: locked
                      ? null
                      : () => _editNumber(
                            context,
                            title: 'SOCKS5 порт',
                            current: settings.socksPort,
                            min: 1,
                            max: 65535,
                            onSave: settings.setSocksPort,
                          ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.http_rounded, color: OrexColors.copper),
                  title: const Text('HTTP'),
                  subtitle: Text('${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.httpPort}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: locked
                      ? null
                      : () => _editNumber(
                            context,
                            title: 'HTTP порт',
                            current: settings.httpPort,
                            min: 1,
                            max: 65535,
                            onSave: settings.setHttpPort,
                          ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.lan_rounded, color: OrexColors.copper),
                  title: const Text('Доступ из локальной сети'),
                  subtitle: const Text('Слушать 0.0.0.0 вместо только localhost'),
                  value: settings.allowLan,
                  onChanged: locked ? null : settings.setAllowLan,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              title: 'VPN',
              subtitle: 'Применяется к TUN/VPN режиму на Android и Windows.',
              children: [
                ListTile(
                  leading: const Icon(Icons.swap_vert_rounded, color: OrexColors.copper),
                  title: const Text('MTU'),
                  subtitle: Text('${settings.mtu} байт'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: locked
                      ? null
                      : () => _editNumber(
                            context,
                            title: 'VPN MTU',
                            current: settings.mtu,
                            min: 1280,
                            max: 9000,
                            onSave: settings.setMtu,
                          ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

Future<void> _editNumber(
  BuildContext context, {
  required String title,
  required int current,
  required int min,
  required int max,
  required Future<void> Function(int value) onSave,
}) async {
  final controller = TextEditingController(text: '$current');
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '$min–$max',
            errorText: error,
          ),
          onSubmitted: (_) async {
            final value = int.tryParse(controller.text.trim());
            if (value == null || value < min || value > max) {
              setState(() => error = 'Допустимо от $min до $max');
              return;
            }
            try {
              await onSave(value);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } on FormatException catch (e) {
              setState(() => error = e.message.toString());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < min || value > max) {
                setState(() => error = 'Допустимо от $min до $max');
                return;
              }
              try {
                await onSave(value);
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

IconData _modeIcon(ConnectionMode mode) => switch (mode) {
      ConnectionMode.vpnTun => Icons.shield_rounded,
      ConnectionMode.systemProxy => Icons.desktop_windows_rounded,
      ConnectionMode.localProxy => Icons.code_rounded,
    };
