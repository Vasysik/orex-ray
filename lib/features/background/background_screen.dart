import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../platform/android/android_startup_controller.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/orex_notice.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/l10n/orex_l10n.dart';

class BackgroundScreen extends StatelessWidget {
  const BackgroundScreen({super.key, required this.settings, this.isAndroid});

  final ConnectionSettingsController settings;
  final bool? isAndroid;

  @override
  Widget build(BuildContext context) {
    final showAndroidNotificationSettings = isAndroid ?? Platform.isAndroid;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsPageHeader(
            title: 'Background operation'.tr,
            subtitle:
                'Statistics frequency, notification and service recovery'.tr,
            icon: Icons.battery_saver_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Statistics'.tr,
            subtitle: 'Infrequent updates wake the CPU less.'.tr,
            children: [
              ListTile(
                leading:
                    Icon(Icons.speed_rounded, color: OrexPalette.of(context).accent),
                title: Text('Interface interval'.tr),
                subtitle: Text(
                  'How often to update speed and counters while OrexRay is open.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.statsIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 1, child: Text('1 s'.tr)),
                    DropdownMenuItem(value: 2, child: Text('2 s'.tr)),
                    DropdownMenuItem(value: 3, child: Text('3 s'.tr)),
                    DropdownMenuItem(value: 5, child: Text('5 s'.tr)),
                    DropdownMenuItem(value: 10, child: Text('10 s'.tr)),
                    DropdownMenuItem(value: 15, child: Text('15 s'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 s'.tr)),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setStatsIntervalSeconds(value);
                  },
                ),
              ),
              if (showAndroidNotificationSettings) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.notifications_active_outlined,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Notification interval'.tr),
                  subtitle: Text(
                    'How often to update the speed in the background notification.'.tr,
                  ),
                  trailing: DropdownButton<int>(
                    value: settings.notificationStatsIntervalSeconds,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: 5, child: Text('5 s'.tr)),
                      DropdownMenuItem(value: 10, child: Text('10 s'.tr)),
                      DropdownMenuItem(value: 15, child: Text('15 s'.tr)),
                      DropdownMenuItem(value: 30, child: Text('30 s'.tr)),
                      DropdownMenuItem(value: 60, child: Text('1 min'.tr)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.setNotificationStatsIntervalSeconds(value);
                      }
                    },
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.timer_outlined,
                  color: OrexPalette.of(context).accent,
                ),
                title: Text('Ping interval'.tr),
                subtitle: Text(
                  showAndroidNotificationSettings
                      ? 'How often to check the active route. In the background it only works when notification ping is enabled.'.tr
                      : 'How often to check the active route while connected.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.pingIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 15, child: Text('15 s'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 s'.tr)),
                    DropdownMenuItem(value: 60, child: Text('1 min'.tr)),
                    DropdownMenuItem(value: 120, child: Text('2 min'.tr)),
                    DropdownMenuItem(value: 300, child: Text('5 min'.tr)),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setPingIntervalSeconds(value);
                  },
                ),
              ),
              if (showAndroidNotificationSettings) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.notifications_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Show notifications'.tr),
                  subtitle: Text(
                    'Visibility is changed in the Android system settings.'.tr,
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => _openAndroidNotificationSettings(context),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.notifications_active_outlined,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Speed in notification'.tr),
                  subtitle: Text(
                    'Show current ↓/↑. If disabled and the interface is closed, the stats loop stops completely.'.tr,
                  ),
                  value: settings.showNotificationSpeed,
                  onChanged: settings.setShowNotificationSpeed,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.network_ping_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Ping in notification'.tr),
                  subtitle: Text(
                    'If disabled and the interface is closed, background ping checks stop completely.'.tr,
                  ),
                  value: settings.showNotificationPing,
                  onChanged: settings.setShowNotificationPing,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Subscriptions'.tr,
            subtitle: 'No background timer: checks run on launch and when returning to the app.'.tr,
            children: [
              ListTile(
                leading: Icon(Icons.cloud_sync_outlined,
                  color: OrexPalette.of(context).accent,
                ),
                title: Text('Subscription auto-update'.tr),
                subtitle: Text(
                  'Update only overdue subscriptions. The provider interval, if specified, is also respected.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.subscriptionAutoUpdateHours,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 0, child: Text('Off'.tr)),
                    DropdownMenuItem(value: 1, child: Text('1 h'.tr)),
                    DropdownMenuItem(value: 6, child: Text('6 h'.tr)),
                    DropdownMenuItem(value: 12, child: Text('12 h'.tr)),
                    DropdownMenuItem(value: 24, child: Text('1 day'.tr)),
                    DropdownMenuItem(value: 72, child: Text('3 days'.tr)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settings.setSubscriptionAutoUpdateHours(value);
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.monitor_heart_outlined,
                  color: OrexPalette.of(context).accent,
                ),
                title: Text('Subscription metadata'.tr),
                subtitle: Text(
                  'Check quota, expiry and links via a lightweight HEAD request on open and when returning to the app. Servers are not downloaded.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.subscriptionMetadataRefreshMinutes,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 0, child: Text('Off'.tr)),
                    DropdownMenuItem(value: 10, child: Text('10 min'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 min'.tr)),
                    DropdownMenuItem(value: 60, child: Text('1 h'.tr)),
                    DropdownMenuItem(value: 360, child: Text('6 h'.tr)),
                    DropdownMenuItem(value: 720, child: Text('12 h'.tr)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settings.setSubscriptionMetadataRefreshMinutes(value);
                    }
                  },
                ),
              ),
            ],
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            SettingsSection(
              title: 'Windows',
              subtitle: 'Window and background behavior of OrexRay.'.tr,
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.login_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Run at Windows startup'.tr),
                  subtitle: Text(
                    'Start hidden in the tray after sign-in.'.tr,
                  ),
                  value: settings.autoStart,
                  onChanged: settings.setAutoStart,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.flash_on_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Connect on launch'.tr),
                  subtitle: Text(
                    'Automatically enable the selected profile after OrexRay starts.'.tr,
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.system_update_alt_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Minimize to tray on close'.tr),
                  subtitle: Text(
                    'If disabled, the close button will stop the connection and quit OrexRay.'.tr,
                  ),
                  value: settings.closeToTray,
                  onChanged: settings.setCloseToTray,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.admin_panel_settings_outlined,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Run as administrator'.tr),
                  subtitle: Text(
                    'The next launch will request UAC. Auto-elevation only works for a protected OrexRay installation in Program Files.'.tr,
                  ),
                  value: settings.windowsRunAsAdministrator,
                  onChanged: settings.setWindowsRunAsAdministrator,
                ),
              ],
            ),
          ],
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            SettingsSection(
              title: 'Android service',
              subtitle:
                  'OrexRay runs as a foreground VPN service even when the interface is closed.'.tr,
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.flash_on_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title:
                      Text('Connect after launch and reboot'.tr),
                  subtitle: Text(
                    'In the app — right after launch. After an Android reboot — restore the last VPN if VPN permission has already been granted.'.tr,
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.restart_alt_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Restore after the process is killed'.tr),
                  subtitle: Text(
                      'Android will bring the last active connection back up when the system allows it'.tr),
                  value: settings.restartServiceOnKill,
                  onChanged: settings.setRestartServiceOnKill,
                ),
                const Divider(height: 1),
                 ListTile(
                  leading: Icon(Icons.eco_outlined, color: OrexPalette.of(context).accent),
                  title: Text('Power saving'.tr),
                  subtitle: Text(
                      'In the background the stats loop stops completely if notification speed is off; the VPN and watchdog keep running.'.tr),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


Future<void> _openAndroidNotificationSettings(BuildContext context) async {
  try {
    await AndroidStartupController.openNotificationSettings();
  } catch (_) {
    if (!context.mounted) return;
    OrexNotice.show(
      context,
      SnackBar(content: Text('Failed to open notification settings'.tr)),
    );
  }
}
