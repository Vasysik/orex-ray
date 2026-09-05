import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../platform/android/android_startup_controller.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';

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
          const SettingsPageHeader(
            title: 'Фоновая работа',
            subtitle:
                'Частота статистики, уведомление и восстановление сервиса',
            icon: Icons.battery_saver_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Статистика',
            subtitle: 'Редкое обновление меньше будит процессор.',
            children: [
              ListTile(
                leading:
                    const Icon(Icons.speed_rounded, color: OrexColors.copper),
                title: const Text('Интервал интерфейса'),
                subtitle: const Text(
                  'Как часто обновлять скорость и счётчики, пока OrexRay открыт.',
                ),
                trailing: DropdownButton<int>(
                  value: settings.statsIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 с')),
                    DropdownMenuItem(value: 2, child: Text('2 с')),
                    DropdownMenuItem(value: 3, child: Text('3 с')),
                    DropdownMenuItem(value: 5, child: Text('5 с')),
                    DropdownMenuItem(value: 10, child: Text('10 с')),
                    DropdownMenuItem(value: 15, child: Text('15 с')),
                    DropdownMenuItem(value: 30, child: Text('30 с')),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setStatsIntervalSeconds(value);
                  },
                ),
              ),
              if (showAndroidNotificationSettings) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Интервал уведомления'),
                  subtitle: const Text(
                    'Как часто обновлять скорость в фоновом уведомлении.',
                  ),
                  trailing: DropdownButton<int>(
                    value: settings.notificationStatsIntervalSeconds,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 с')),
                      DropdownMenuItem(value: 10, child: Text('10 с')),
                      DropdownMenuItem(value: 15, child: Text('15 с')),
                      DropdownMenuItem(value: 30, child: Text('30 с')),
                      DropdownMenuItem(value: 60, child: Text('1 мин')),
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
                leading: const Icon(
                  Icons.timer_outlined,
                  color: OrexColors.copper,
                ),
                title: const Text('Интервал пинга'),
                subtitle: Text(
                  showAndroidNotificationSettings
                      ? 'Как часто проверять активный маршрут. В фоне работает '
                          'только при включённом пинге в уведомлении.'
                      : 'Как часто проверять активный маршрут во время подключения.',
                ),
                trailing: DropdownButton<int>(
                  value: settings.pingIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 15, child: Text('15 с')),
                    DropdownMenuItem(value: 30, child: Text('30 с')),
                    DropdownMenuItem(value: 60, child: Text('1 мин')),
                    DropdownMenuItem(value: 120, child: Text('2 мин')),
                    DropdownMenuItem(value: 300, child: Text('5 мин')),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setPingIntervalSeconds(value);
                  },
                ),
              ),
              if (showAndroidNotificationSettings) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.notifications_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Показывать уведомления'),
                  subtitle: const Text(
                    'Видимость меняется в системных настройках Android.',
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _openAndroidNotificationSettings(context),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Скорость в уведомлении'),
                  subtitle: const Text(
                    'Показывать текущие ↓/↑. Если выключено и интерфейс закрыт, '
                    'stats-loop полностью останавливается.',
                  ),
                  value: settings.showNotificationSpeed,
                  onChanged: settings.setShowNotificationSpeed,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.network_ping_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Пинг в уведомлении'),
                  subtitle: const Text(
                    'Если выключено и интерфейс закрыт, фоновые проверки пинга '
                    'полностью останавливаются.',
                  ),
                  value: settings.showNotificationPing,
                  onChanged: settings.setShowNotificationPing,
                ),
              ],
            ],
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            SettingsSection(
              title: 'Windows',
              subtitle: 'Поведение окна и фоновой работы OrexRay.',
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.login_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Запускать вместе с Windows'),
                  subtitle: const Text(
                    'Стартовать скрыто в трее после входа в систему.',
                  ),
                  value: settings.autoStart,
                  onChanged: settings.setAutoStart,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.flash_on_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Подключаться при запуске'),
                  subtitle: const Text(
                    'Автоматически включать выбранный профиль после старта OrexRay.',
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.system_update_alt_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Сворачивать в трей при закрытии'),
                  subtitle: const Text(
                    'Если выключено, крестик остановит подключение и '
                    'завершит OrexRay.',
                  ),
                  value: settings.closeToTray,
                  onChanged: settings.setCloseToTray,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Запускать с правами администратора'),
                  subtitle: const Text(
                    'На следующем запуске запросит UAC. Автоповышение работает '
                    'только для защищённой установки OrexRay в Program Files.',
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
                  'OrexRay работает как foreground VPN-service, даже когда интерфейс закрыт.',
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.flash_on_rounded,
                    color: OrexColors.copper,
                  ),
                  title:
                      const Text('Подключаться после запуска и перезагрузки'),
                  subtitle: const Text(
                    'В приложении — сразу после старта. После reboot Android — восстановить последний VPN, если разрешение VPN уже выдано.',
                  ),
                  value: settings.autoConnectOnStartup,
                  onChanged: settings.setAutoConnectOnStartup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.restart_alt_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Восстанавливать после убийства процесса'),
                  subtitle: const Text(
                      'Android повторно поднимет последнее активное подключение, когда это разрешено системой'),
                  value: settings.restartServiceOnKill,
                  onChanged: settings.setRestartServiceOnKill,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.eco_outlined, color: OrexColors.copper),
                  title: Text('Энергосбережение'),
                  subtitle: Text(
                      'В фоне stats-loop полностью останавливается, если скорость в уведомлении выключена; VPN и watchdog продолжают работать.'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть настройки уведомлений')),
    );
  }
}
