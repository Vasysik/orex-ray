import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';

class BackgroundScreen extends StatelessWidget {
  const BackgroundScreen({super.key, required this.settings});

  final ConnectionSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SettingsPageHeader(
            title: 'Фоновая работа',
            subtitle: 'Частота статистики, уведомление и восстановление сервиса',
            icon: Icons.battery_saver_rounded,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Статистика',
            subtitle: 'Редкое обновление меньше будит процессор.',
            children: [
              ListTile(
                leading: const Icon(Icons.speed_rounded, color: OrexColors.copper),
                title: const Text('Интервал обновления'),
                subtitle: Text('Каждые ${settings.statsIntervalSeconds} с'),
                trailing: DropdownButton<int>(
                  value: settings.statsIntervalSeconds,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 с')),
                    DropdownMenuItem(value: 2, child: Text('2 с')),
                    DropdownMenuItem(value: 5, child: Text('5 с')),
                    DropdownMenuItem(value: 10, child: Text('10 с')),
                  ],
                  onChanged: (value) {
                    if (value != null) settings.setStatsIntervalSeconds(value);
                  },
                ),
              ),
              if (Platform.isAndroid) ...[
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Скорость в уведомлении'),
                  subtitle: const Text('Показывать текущие ↓/↑ без звука и вибрации'),
                  value: settings.showNotificationSpeed,
                  onChanged: settings.setShowNotificationSpeed,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.network_ping_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Ping в уведомлении'),
                  subtitle: const Text('Показывать последнюю измеренную задержку профиля'),
                  value: settings.showNotificationPing,
                  onChanged: settings.setShowNotificationPing,
                ),
              ],
            ],
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            SettingsSection(
              title: 'Android service',
              subtitle: 'OrexRay работает как foreground VPN-service, даже когда интерфейс закрыт.',
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.restart_alt_rounded,
                    color: OrexColors.copper,
                  ),
                  title: const Text('Восстанавливать после убийства процесса'),
                  subtitle: const Text('Android повторно поднимет последнее активное подключение, когда это разрешено системой'),
                  value: settings.restartServiceOnKill,
                  onChanged: settings.setRestartServiceOnKill,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.eco_outlined, color: OrexColors.copper),
                  title: Text('Энергосбережение'),
                  subtitle: Text('В фоне Flutter-интерфейс не обновляется; работает только VPN-service и выбранный таймер статистики.'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
