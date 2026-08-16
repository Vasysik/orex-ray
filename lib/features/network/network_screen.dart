import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/orex_edit_dialog.dart';
import '../../shared/widgets/settings_section.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key, required this.settings});

  final ConnectionSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SettingsPageHeader(
            title: 'Сеть',
            subtitle: 'DNS и маршрутизация Xray',
            icon: Icons.public_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'DNS',
            subtitle: 'VPN-применение требует переподключения.',
            children: [
              RadioGroup<DnsPreset>(
                groupValue: settings.dnsPreset,
                onChanged: (preset) {
                  if (preset != null) settings.setDnsPreset(preset);
                },
                child: Column(
                  children: [
                    for (final preset in DnsPreset.values)
                      RadioListTile<DnsPreset>(
                        value: preset,
                        secondary: Icon(
                          preset == DnsPreset.custom
                              ? Icons.edit_rounded
                              : Icons.dns_rounded,
                          color: OrexColors.copper,
                        ),
                        title: Text(preset.title),
                        subtitle: Text(
                          preset == DnsPreset.custom &&
                                  settings.customDns.isNotEmpty
                              ? settings.customDns
                              : preset.description,
                        ),
                      ),
                  ],
                ),
              ),
              if (settings.dnsPreset == DnsPreset.custom) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded,
                      color: OrexColors.copper),
                  title: const Text('Адреса DNS'),
                  subtitle: Text(
                    settings.customDns.isEmpty
                        ? 'Не заданы'
                        : settings.customDns,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editCustomDns(context, settings),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Маршрутизация',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.home_work_outlined,
                    color: OrexColors.copper),
                title: const Text('Локальные сети напрямую'),
                subtitle:
                    const Text('Не отправлять частные IP-диапазоны через Xray'),
                value: settings.bypassPrivateNetworks,
                onChanged: settings.setBypassPrivateNetworks,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.manage_search_rounded,
                    color: OrexColors.copper),
                title: const Text('Sniffing протоколов'),
                subtitle: const Text(
                    'Определять HTTP, TLS и QUIC для корректной маршрутизации'),
                value: settings.sniffingEnabled,
                onChanged: settings.setSniffingEnabled,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Проверка задержки',
            subtitle: 'Публичный адрес для измерения задержки',
            children: [
              RadioGroup<LatencyProbePreset>(
                groupValue: settings.latencyProbePreset,
                onChanged: (preset) {
                  if (preset != null) {
                    _selectLatencyProbePreset(context, settings, preset);
                  }
                },
                child: Column(
                  children: [
                    for (final preset in LatencyProbePreset.values)
                      RadioListTile<LatencyProbePreset>(
                        value: preset,
                        secondary: const Icon(
                          Icons.speed_rounded,
                          color: OrexColors.copper,
                        ),
                        title: Text(preset.title),
                        subtitle: Text(
                          preset == LatencyProbePreset.custom &&
                                  settings.customLatencyProbeUrl.isNotEmpty
                              ? settings.customLatencyProbeUrl
                              : preset.description,
                        ),
                      ),
                  ],
                ),
              ),
              if (settings.latencyProbePreset == LatencyProbePreset.custom)
                const Divider(height: 1),
              if (settings.latencyProbePreset == LatencyProbePreset.custom)
                ListTile(
                  leading: const Icon(
                    Icons.link_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Изменить URL'),
                  subtitle: Text(settings.customLatencyProbeUrl),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editCustomLatencyProbeUrl(context, settings),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _selectLatencyProbePreset(
  BuildContext context,
  ConnectionSettingsController settings,
  LatencyProbePreset preset,
) async {
  if (preset == LatencyProbePreset.custom &&
      settings.customLatencyProbeUrl.isEmpty) {
    await _editCustomLatencyProbeUrl(context, settings);
    return;
  }
  await settings.setLatencyProbePreset(preset);
}

Future<void> _editCustomLatencyProbeUrl(
  BuildContext context,
  ConnectionSettingsController settings,
) {
  return showOrexEditDialog(
    context,
    title: 'URL проверки задержки',
    initialValue: settings.customLatencyProbeUrl,
    keyboardType: TextInputType.url,
    textInputAction: TextInputAction.done,
    labelText: 'https://example.com/health',
    helperText: 'Только публичный HTTP(S) адрес',
    validator: ConnectionSettingsController.validateLatencyProbeUrl,
    onSave: settings.setCustomLatencyProbeUrl,
  );
}

Future<void> _editCustomDns(
  BuildContext context,
  ConnectionSettingsController settings,
) {
  return showOrexEditDialog(
    context,
    title: 'Свой DNS',
    initialValue: settings.customDns,
    maxLines: 3,
    hintText: '9.9.9.9, 149.112.112.112',
    helperText: 'Разделяй адреса пробелами или запятыми',
    onSave: (value) async {
      await settings.setCustomDns(value);
      await settings.setDnsPreset(DnsPreset.custom);
    },
  );
}
