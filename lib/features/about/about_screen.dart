import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';
import '../../shared/widgets/squirrel_mascot.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const version = '0.6.2';
  static const buildNumber = '1';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsPageHeader(
          title: 'О приложении',
          subtitle: 'OrexRay — Xray-клиент для Android и Windows',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 22),
        const Center(
          child: SquirrelMascot(size: 128, caption: 'Белочка защищает маршрут'),
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'Версия',
          children: [
            const ListTile(
              leading: Icon(Icons.apps_rounded, color: OrexColors.copper),
              title: Text('OrexRay'),
              subtitle: Text('Версия $version · сборка $buildNumber'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: OrexColors.copper),
              title: const Text('Скопировать информацию'),
              subtitle: const Text('Для баг-репорта и диагностики'),
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: 'OrexRay $version+$buildNumber'),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Информация скопирована')),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SettingsSection(
          title: 'Движок',
          children: [
            ListTile(
              leading: Icon(Icons.hub_rounded, color: OrexColors.copper),
              title: Text('Xray Core'),
              subtitle: Text('VLESS · REALITY · TLS · TUN · SOCKS5 · HTTP'),
            ),
          ],
        ),
      ],
    );
  }
}
