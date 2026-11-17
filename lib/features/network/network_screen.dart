import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/orex_edit_dialog.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/l10n/orex_l10n.dart';

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
          SettingsPageHeader(
            title: 'Network'.tr,
            subtitle: 'Xray DNS and routing'.tr,
            icon: Icons.public_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'DNS',
            subtitle: 'Applying to the VPN requires reconnecting.'.tr,
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
                          color: OrexPalette.of(context).accent,
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
                  leading: Icon(Icons.edit_note_rounded,
                      color: OrexPalette.of(context).accent),
                  title: Text('DNS addresses'.tr),
                  subtitle: Text(
                    settings.customDns.isEmpty
                        ? 'Not set'.tr
                        : settings.customDns,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => _editCustomDns(context, settings),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Routing'.tr,
            children: [
              SwitchListTile(
                secondary: Icon(Icons.home_work_outlined,
                    color: OrexPalette.of(context).accent),
                title: Text('Local networks directly'.tr),
                subtitle:
                    Text('Do not send private IP ranges through Xray'.tr),
                value: settings.bypassPrivateNetworks,
                onChanged: settings.setBypassPrivateNetworks,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: Icon(Icons.manage_search_rounded,
                    color: OrexPalette.of(context).accent),
                title: Text('Protocol sniffing'.tr),
                subtitle: Text(
                    'Detect HTTP, TLS and QUIC for correct routing'.tr),
                value: settings.sniffingEnabled,
                onChanged: settings.setSniffingEnabled,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Latency check'.tr,
            subtitle: 'Public address for latency measurement'.tr,
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
                        secondary: Icon(Icons.speed_rounded,
                          color: OrexPalette.of(context).accent,
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
                  leading: Icon(Icons.link_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Change URL'.tr),
                  subtitle: Text(settings.customLatencyProbeUrl),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  mouseCursor: SystemMouseCursors.click,
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
    title: 'Latency check URL'.tr,
    initialValue: settings.customLatencyProbeUrl,
    keyboardType: TextInputType.url,
    textInputAction: TextInputAction.done,
    labelText: 'https://example.com/health',
    helperText: 'Public HTTP(S) address only'.tr,
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
    title: 'Custom DNS'.tr,
    initialValue: settings.customDns,
    maxLines: 3,
    hintText: '9.9.9.9, 149.112.112.112',
    helperText: 'Separate addresses with spaces or commas'.tr,
    onSave: (value) async {
      await settings.setCustomDns(value);
      await settings.setDnsPreset(DnsPreset.custom);
    },
  );
}
