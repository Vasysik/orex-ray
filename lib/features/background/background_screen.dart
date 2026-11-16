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
            title: 'Фоновая работа'.tr,
            subtitle:
                'Частота статистики, уведомление и восстановление сервиса'.tr,
            icon: Icons.battery_saver_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Статистика'.tr,
            subtitle: 'Редкое обновление меньше будит процессор.'.tr,
            children: [
              ListTile(
                leading:
                    Icon(Icons.speed_rounded, color: OrexPalette.of(context).accent),
                title: Text('Интервал интерфейса'.tr),
                subtitle: Text(
                  'Как часто обновлять скорость и счётчики, пока OrexRay открыт.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.statsIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 1, child: Text('1 с'.tr)),
                    DropdownMenuItem(value: 2, child: Text('2 с'.tr)),
                    DropdownMenuItem(value: 3, child: Text('3 с'.tr)),
                    DropdownMenuItem(value: 5, child: Text('5 с'.tr)),
                    DropdownMenuItem(value: 10, child: Text('10 с'.tr)),
                    DropdownMenuItem(value: 15, child: Text('15 с'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 с'.tr)),
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
                  title: Text('Интервал уведомления'.tr),
                  subtitle: Text(
                    'Как часто обновлять скорость в фоновом уведомлении.'.tr,
                  ),
                  trailing: DropdownButton<int>(
                    value: settings.notificationStatsIntervalSeconds,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: 5, child: Text('5 с'.tr)),
                      DropdownMenuItem(value: 10, child: Text('10 с'.tr)),
                      DropdownMenuItem(value: 15, child: Text('15 с'.tr)),
                      DropdownMenuItem(value: 30, child: Text('30 с'.tr)),
                      DropdownMenuItem(value: 60, child: Text('1 мин'.tr)),
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
                title: Text('Интервал пинга'.tr),
                subtitle: Text(
                  showAndroidNotificationSettings
                      ? 'Как часто проверять активный маршрут. В фоне работает только при включённом пинге в уведомлении.'.tr
                      : 'Как часто проверять активный маршрут во время подключения.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.pingIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 15, child: Text('15 с'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 с'.tr)),
                    DropdownMenuItem(value: 60, child: Text('1 мин'.tr)),
                    DropdownMenuItem(value: 120, child: Text('2 мин'.tr)),
                    DropdownMenuItem(value: 300, child: Text('5 мин'.tr)),
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
                  title: Text('Показывать уведомления'.tr),
                  subtitle: Text(
                    'Видимость меняется в системных настройках Android.'.tr,
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
                  title: Text('Скорость в уведомлении'.tr),
                  subtitle: Text(
                    'Показывать текущие ↓/↑. Если выключено и интерфейс закрыт, stats-loop полностью останавливается.'.tr,
                  ),
                  value: settings.showNotificationSpeed,
                  onChanged: settings.setShowNotificationSpeed,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.network_ping_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Пинг в уведомлении'.tr),
                  subtitle: Text(
                    'Если выключено и интерфейс закрыт, фоновые проверки пинга полностью останавливаются.'.tr,
                  ),
                  value: settings.showNotificationPing,
                  onChanged: settings.setShowNotificationPing,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Подписки'.tr,
            subtitle: 'Без фонового таймера: проверка выполняется при запуске и возврате в приложение.'.tr,
            children: [
              ListTile(
                leading: Icon(Icons.cloud_sync_outlined,
                  color: OrexPalette.of(context).accent,
                ),
                title: Text('Автообновление подписок'.tr),
                subtitle: Text(
                  'Обновлять только просроченные подписки. Интервал провайдера, если он указан, тоже учитывается.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.subscriptionAutoUpdateHours,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 0, child: Text('Выкл.'.tr)),
                    DropdownMenuItem(value: 1, child: Text('1 ч'.tr)),
                    DropdownMenuItem(value: 6, child: Text('6 ч'.tr)),
                    DropdownMenuItem(value: 12, child: Text('12 ч'.tr)),
                    DropdownMenuItem(value: 24, child: Text('1 день'.tr)),
                    DropdownMenuItem(value: 72, child: Text('3 дня'.tr)),
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
                title: Text('Метаданные подписок'.tr),
                subtitle: Text(
                  'Проверять квоту, срок и ссылки через лёгкий HEAD-запрос при открытии и возврате в приложение. Серверы не скачиваются.'.tr,
                ),
                trailing: DropdownButton<int>(
                  value: settings.subscriptionMetadataRefreshMinutes,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 0, child: Text('Выкл.'.tr)),
                    DropdownMenuItem(value: 10, child: Text('10 мин'.tr)),
                    DropdownMenuItem(value: 30, child: Text('30 мин'.tr)),
                    DropdownMenuItem(value: 60, child: Text('1 ч'.tr)),
                    DropdownMenuItem(value: 360, child: Text('6 ч'.tr)),
                    DropdownMenuItem(value: 720, child: Text('12 ч'.tr)),
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
              subtitle: 'Поведение окна и фоновой работы OrexRay.'.tr,
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.login_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Запускать вместе с Windows'.tr),
                  subtitle: Text(
                    'Стартовать скрыто в трее после входа в систему.'.tr,
                  ),
                  value: settings.autoStart,
                  onChanged: settings.setAutoStart,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.flash_on_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Подключаться при запуске'.tr),
                  subtitle: Text(
                    'Автоматически включать выбранный профиль после старта OrexRay.'.tr,
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.system_update_alt_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Сворачивать в трей при закрытии'.tr),
                  subtitle: Text(
                    'Если выключено, крестик остановит подключение и завершит OrexRay.'.tr,
                  ),
                  value: settings.closeToTray,
                  onChanged: settings.setCloseToTray,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.admin_panel_settings_outlined,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Запускать с правами администратора'.tr),
                  subtitle: Text(
                    'На следующем запуске запросит UAC. Автоповышение работает только для защищённой установки OrexRay в Program Files.'.tr,
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
                  'OrexRay работает как foreground VPN-service, даже когда интерфейс закрыт.'.tr,
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.flash_on_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title:
                      Text('Подключаться после запуска и перезагрузки'.tr),
                  subtitle: Text(
                    'В приложении — сразу после старта. После reboot Android — восстановить последний VPN, если разрешение VPN уже выдано.'.tr,
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.restart_alt_rounded,
                    color: OrexPalette.of(context).accent,
                  ),
                  title: Text('Восстанавливать после убийства процесса'.tr),
                  subtitle: Text(
                      'Android повторно поднимет последнее активное подключение, когда это разрешено системой'.tr),
                  value: settings.restartServiceOnKill,
                  onChanged: settings.setRestartServiceOnKill,
                ),
                const Divider(height: 1),
                 ListTile(
                  leading: Icon(Icons.eco_outlined, color: OrexPalette.of(context).accent),
                  title: Text('Энергосбережение'.tr),
                  subtitle: Text(
                      'В фоне stats-loop полностью останавливается, если скорость в уведомлении выключена; VPN и watchdog продолжают работать.'.tr),
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
      SnackBar(content: Text('Не удалось открыть настройки уведомлений'.tr)),
    );
  }
}
