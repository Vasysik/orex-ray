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
            subtitle: 'DNS, маршрутизация и диагностика Xray',
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
                          preset == DnsPreset.custom && settings.customDns.isNotEmpty
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
                  leading: const Icon(Icons.edit_note_rounded, color: OrexColors.copper),
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
                secondary: const Icon(Icons.home_work_outlined, color: OrexColors.copper),
                title: const Text('Локальные сети напрямую'),
                subtitle: const Text('Не отправлять частные IP-диапазоны через Xray'),
                value: settings.bypassPrivateNetworks,
                onChanged: settings.setBypassPrivateNetworks,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.manage_search_rounded, color: OrexColors.copper),
                title: const Text('Sniffing протоколов'),
                subtitle: const Text('Определять HTTP, TLS и QUIC для корректной маршрутизации'),
                value: settings.sniffingEnabled,
                onChanged: settings.setSniffingEnabled,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Диагностика',
            subtitle: 'Более подробный уровень создаёт больше логов Xray.',
            children: [
              ListTile(
                leading: const Icon(Icons.terminal_rounded, color: OrexColors.copper),
                title: const Text('Уровень логов Xray'),
                subtitle: Text(_logLevelTitle(settings.logLevel)),
                trailing: DropdownButton<String>(
                  value: settings.logLevel,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'error', child: Text('Ошибки')),
                    DropdownMenuItem(value: 'warning', child: Text('Предупреждения')),
                    DropdownMenuItem(value: 'info', child: Text('Информация')),
                    DropdownMenuItem(value: 'debug', child: Text('Отладка')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _setLogLevel(context, settings, value);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


Future<void> _setLogLevel(
  BuildContext context,
  ConnectionSettingsController settings,
  String value,
) async {
  if (value == 'info' || value == 'debug') {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.visibility_outlined),
            title: const Text('Подробные сетевые логи'),
            content: const Text(
              'На уровнях «Информация» и «Отладка» Xray может писать в logcat '
              'адреса назначения и другую сетевую диагностику. Используй эти '
              'режимы только временно при поиске проблемы.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Включить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
  }
  await settings.setLogLevel(value);
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

String _logLevelTitle(String value) => switch (value) {
      'warning' => 'Предупреждения',
      'info' => 'Информация',
      'debug' => 'Отладка',
      _ => 'Только ошибки',
    };
