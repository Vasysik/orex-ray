import 'package:flutter/material.dart';

import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/theme/theme_controller.dart';
import '../home/tunnel_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.theme,
    required this.tunnel,
  });

  final ThemeController theme;
  final TunnelController tunnel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tunnel,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Настройки', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Поведение, оформление и режим подключения',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Оформление',
            children: [
              RadioGroup<ThemeMode>(
                groupValue: theme.mode,
                onChanged: (mode) {
                  if (mode != null) theme.setMode(mode);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      title: Text('Тёмная'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      title: Text('Светлая'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      title: Text('Системная'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Подключение',
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
                        enabled: tunnel.canChangeMode,
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
              if (!tunnel.canChangeMode) ...[
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Режим заблокирован'),
                  subtitle: Text('Сначала отключите OrexRay.'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: 'Сеть',
            children: [
              ListTile(
                leading: Icon(Icons.dns_outlined, color: OrexColors.copper),
                title: Text('DNS'),
                subtitle: Text('Автоматически'),
              ),
              Divider(height: 1),
              SwitchListTile(
                secondary: Icon(Icons.power_rounded, color: OrexColors.copper),
                title: Text('Автоподключение'),
                subtitle: Text('Будет добавлено после стабилизации движков'),
                value: false,
                onChanged: null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: 'О приложении',
            children: [
              ListTile(
                leading: Icon(Icons.pets_rounded, color: OrexColors.copper),
                title: Text('OrexRay'),
                subtitle: Text('Версия 0.6.1 · VPN + System Proxy + Local Proxy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 1.1,
                  color: OrexColors.copper,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        GlassPanel(borderRadius: 20, child: Column(children: children)),
      ],
    );
  }
}

IconData _modeIcon(ConnectionMode mode) => switch (mode) {
      ConnectionMode.vpnTun => Icons.shield_rounded,
      ConnectionMode.systemProxy => Icons.desktop_windows_rounded,
      ConnectionMode.localProxy => Icons.code_rounded,
    };
