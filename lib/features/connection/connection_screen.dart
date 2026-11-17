import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/orex_confirm_dialog.dart';
import '../../shared/widgets/orex_edit_dialog.dart';
import '../../shared/widgets/orex_proxy_copy.dart';
import '../../shared/widgets/settings_section.dart';
import '../home/tunnel_controller.dart';
import '../../shared/l10n/orex_l10n.dart';

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
      animation: Listenable.merge([tunnel.profileUiChanges, settings]),
      builder: (context, _) {
        final locked = !tunnel.canChangeMode;
        final disabledColor = Theme.of(context).disabledColor;
        final editableIconColor = locked ? disabledColor : OrexPalette.of(context).accent;
        final chevronColor = locked ? disabledColor : null;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsPageHeader(
              title: 'Connection'.tr,
              subtitle: 'Operating mode and OrexRay local entry points'.tr,
              icon: Icons.route_rounded,
            ),
            const SizedBox(height: 22),
            SettingsSection(
              title: 'Mode'.tr,
              subtitle: locked
                  ? 'Disconnect OrexRay first to change the mode.'.tr
                  : 'Choose which traffic should go through Xray.'.tr,
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
                            color: OrexPalette.of(context).accent,
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
              title: 'Network'.tr,
              subtitle: 'Local SOCKS5/HTTP ports and access parameters.'.tr,
              children: [
                ListTile(
                  enabled: !locked,
                  leading: Icon(Icons.cable_rounded, color: editableIconColor),
                  title: const Text('SOCKS5'),
                  subtitle: Text(
                    '${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.socksPort}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProxyCopyButton(
                        protocol: 'SOCKS5',
                        scheme: 'socks5',
                        port: settings.socksPort,
                        allowLan: settings.allowLan,
                      ),
                      Icon(Icons.chevron_right_rounded, color: chevronColor),
                    ],
                  ),
                  mouseCursor: locked
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  onTap: locked
                      ? null
                      : () => _editNumber(
                            context,
                            title: 'SOCKS5 port'.tr,
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
                    '${settings.allowLan ? '0.0.0.0' : '127.0.0.1'}:${settings.httpPort}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProxyCopyButton(
                        protocol: 'HTTP',
                        scheme: 'http',
                        port: settings.httpPort,
                        allowLan: settings.allowLan,
                      ),
                      Icon(Icons.chevron_right_rounded, color: chevronColor),
                    ],
                  ),
                  mouseCursor: locked
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  onTap: locked
                      ? null
                      : () => _editNumber(
                            context,
                            title: 'HTTP port'.tr,
                            current: settings.httpPort,
                            min: 1,
                            max: 65535,
                            onSave: settings.setHttpPort,
                          ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary:
                      Icon(Icons.lan_rounded, color: OrexPalette.of(context).accent),
                  title: Text('LAN access'.tr),
                  subtitle:
                      Text('Listen on 0.0.0.0 instead of localhost only'.tr),
                  value: settings.allowLan,
                  onChanged: locked
                      ? null
                      : (value) => _setAllowLan(context, settings, value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.multiple_stop_rounded,
                      color: OrexPalette.of(context).accent),
                  title: Text('Proxy alongside VPN'.tr),
                  subtitle: Text(
                    'Keep SOCKS5 and HTTP available while TUN/VPN is running'.tr,
                  ),
                  value: settings.localProxyInVpn,
                  onChanged: locked ? null : settings.setLocalProxyInVpn,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsSection(
              title: 'VPN',
              subtitle: 'Applies to TUN/VPN mode on Android and Windows.'.tr,
              children: [
                ListTile(
                  enabled: !locked,
                  leading: Icon(
                    Icons.swap_vert_rounded,
                    color: editableIconColor,
                  ),
                  title: const Text('MTU'),
                  subtitle: Text('{} bytes'.trf([settings.mtu])),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor,
                  ),
                  mouseCursor: locked
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
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


/// A compact, independent action beside the port editor's chevron.
/// It remains available even while the surrounding ListTile is disabled.
class _ProxyCopyButton extends StatelessWidget {
  const _ProxyCopyButton({
    required this.protocol,
    required this.scheme,
    required this.port,
    required this.allowLan,
  });

  final String protocol;
  final String scheme;
  final int port;
  final bool allowLan;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Копировать $protocol',
      icon: const Icon(Icons.copy_rounded, size: 19),
      onPressed: () {
        final box = context.findRenderObject();
        if (box is! RenderBox) return;
        OrexProxyCopy.showAddressMenu(
          context,
          globalPosition: box.localToGlobal(box.size.center(Offset.zero)),
          protocol: protocol,
          scheme: scheme,
          port: port,
          allowLan: allowLan,
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
        builder: (dialogContext) => OrexConfirmDialog(
          icon: Icons.warning_amber_rounded,
          title: 'Expose the proxy to the LAN?'.tr,
          content: Text(
            'OrexRay SOCKS5 and HTTP proxies currently require no password. Once enabled, other devices on this LAN will be able to use your proxy unless a firewall blocks the connection. Enable this only on a trusted network.'.tr,
          ),
          confirmLabel: 'Allow access'.tr,
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
