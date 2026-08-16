import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/orex_edit_dialog.dart';
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
        final disabledColor = Theme.of(context).disabledColor;
        final editableIconColor = locked ? disabledColor : OrexColors.copper;
        final chevronColor = locked ? disabledColor : null;
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
              title: 'Сеть',
              subtitle:
                  'Эти порты используются и режимом системного прокси Windows.',
              children: [
                ListTile(
                  enabled: !locked,
                  leading: Icon(Icons.cable_rounded, color: editableIconColor),
                  title: const Text('SOCKS5'),
                  subtitle: Text(
                      '${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.socksPort}'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor,
                  ),
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
                  enabled: !locked,
                  leading: Icon(Icons.http_rounded, color: editableIconColor),
                  title: const Text('HTTP'),
                  subtitle: Text(
                      '${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.httpPort}'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor,
                  ),
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
                  secondary:
                      const Icon(Icons.lan_rounded, color: OrexColors.copper),
                  title: const Text('Доступ из локальной сети'),
                  subtitle:
                      const Text('Слушать 0.0.0.0 вместо только localhost'),
                  value: settings.allowLan,
                  onChanged: locked
                      ? null
                      : (value) => _setAllowLan(context, settings, value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.multiple_stop_rounded,
                      color: OrexColors.copper),
                  title: const Text('Прокси параллельно VPN'),
                  subtitle: const Text(
                    'Оставлять SOCKS5 и HTTP доступными, пока работает TUN/VPN',
                  ),
                  value: settings.localProxyInVpn,
                  onChanged: locked ? null : settings.setLocalProxyInVpn,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              title: 'VPN',
              subtitle: 'Применяется к TUN/VPN режиму на Android и Windows.',
              children: [
                ListTile(
                  enabled: !locked,
                  leading: Icon(
                    Icons.swap_vert_rounded,
                    color: editableIconColor,
                  ),
                  title: const Text('MTU'),
                  subtitle: Text('${settings.mtu} байт'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor,
                  ),
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

Future<void> _setAllowLan(
  BuildContext context,
  ConnectionSettingsController settings,
  bool value,
) async {
  if (!value) {
    await settings.setAllowLan(false);
    return;
  }

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Открыть прокси в локальную сеть?'),
          content: const Text(
            'SOCKS5 и HTTP-прокси OrexRay сейчас не требуют пароль. '
            'После включения другие устройства в этой локальной сети смогут '
            'использовать твой прокси, если соединение не блокирует firewall. '
            'Включай это только в доверенной сети.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Открыть доступ'),
            ),
          ],
        ),
      ) ??
      false;
  if (confirmed) await settings.setAllowLan(true);
}

Future<void> _editNumber(
  BuildContext context, {
  required String title,
  required int current,
  required int min,
  required int max,
  required Future<void> Function(int value) onSave,
}) {
  return showOrexEditDialog(
    context,
    title: title,
    initialValue: '$current',
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    labelText: '$min–$max',
    validator: (rawValue) {
      final value = int.tryParse(rawValue.trim());
      if (value == null || value < min || value > max) {
        return 'Допустимо от $min до $max';
      }
      return null;
    },
    onSave: (rawValue) => onSave(int.parse(rawValue.trim())),
  );
}

IconData _modeIcon(ConnectionMode mode) => switch (mode) {
      ConnectionMode.vpnTun => Icons.shield_rounded,
      ConnectionMode.systemProxy => Icons.desktop_windows_rounded,
      ConnectionMode.localProxy => Icons.code_rounded,
    };
