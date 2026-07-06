import 'package:flutter/material.dart';

import '../../core/profiles/profiles_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/theme_controller.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../home/home_screen.dart';
import '../home/tunnel_controller.dart';
import '../profiles/profiles_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.tunnel,
    required this.profiles,
    required this.theme,
  });

  final TunnelController tunnel;
  final ProfilesController profiles;
  final ThemeController theme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(tunnel: widget.tunnel),
      ProfilesScreen(profiles: widget.profiles),
      SettingsScreen(theme: widget.theme, tunnel: widget.tunnel),
    ];

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              if (desktop) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GlassPanel(
                        borderRadius: 24,
                        child: SizedBox(
                          width: 98,
                          child: NavigationRail(
                            selectedIndex: _index,
                            onDestinationSelected: (value) =>
                                setState(() => _index = value),
                            labelType: NavigationRailLabelType.all,
                            leading: const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: SquirrelMascot(size: 50, compact: true),
                            ),
                            destinations: const [
                              NavigationRailDestination(
                                icon: Icon(Icons.power_settings_new_rounded),
                                label: Text('Главная'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.storage_rounded),
                                label: Text('Профили'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.tune_rounded),
                                label: Text('Настройки'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassPanel(
                          borderRadius: 24,
                          opacity: 0.30,
                          child: IndexedStack(index: _index, children: pages),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Expanded(child: IndexedStack(index: _index, children: pages)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: GlassPanel(
                      borderRadius: 22,
                      child: NavigationBar(
                        selectedIndex: _index,
                        onDestinationSelected: (value) =>
                            setState(() => _index = value),
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.power_settings_new_rounded),
                            label: 'Главная',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.storage_rounded),
                            label: 'Профили',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.tune_rounded),
                            label: 'Настройки',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
