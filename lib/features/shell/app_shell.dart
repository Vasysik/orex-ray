import 'package:flutter/material.dart';

import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/theme_controller.dart';
import '../about/about_screen.dart';
import '../appearance/appearance_screen.dart';
import '../connection/connection_screen.dart';
import '../home/home_screen.dart';
import '../home/tunnel_controller.dart';
import '../network/network_screen.dart';
import '../profiles/profiles_screen.dart';
import '../settings/more_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.tunnel,
    required this.profiles,
    required this.theme,
    required this.settings,
  });

  final TunnelController tunnel;
  final ProfilesController profiles;
  final ThemeController theme;
  final ConnectionSettingsController settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _moreIndex = 6;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(tunnel: widget.tunnel),
      ProfilesScreen(profiles: widget.profiles),
      ConnectionScreen(tunnel: widget.tunnel, settings: widget.settings),
      NetworkScreen(settings: widget.settings),
      AppearanceScreen(theme: widget.theme),
      const AboutScreen(),
      MoreScreen(
        onOpenNetwork: () => setState(() => _index = 3),
        onOpenAppearance: () => setState(() => _index = 4),
        onOpenAbout: () => setState(() => _index = 5),
      ),
    ];

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              if (desktop) {
                final desktopIndex = _index == _moreIndex ? 3 : _index;
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GlassPanel(
                        borderRadius: 24,
                        child: SizedBox(
                          width: 112,
                          child: NavigationRail(
                            selectedIndex: desktopIndex,
                            onDestinationSelected: (value) =>
                                setState(() => _index = value),
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: -0.72,
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
                                icon: Icon(Icons.route_rounded),
                                label: Text('Подключение'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.public_rounded),
                                label: Text('Сеть'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.palette_outlined),
                                label: Text('Интерфейс'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.info_outline_rounded),
                                label: Text('О приложении'),
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
                          child: IndexedStack(
                            index: desktopIndex,
                            children: pages.take(6).toList(growable: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final mobileSelected = _index <= 2 ? _index : 3;
              return Column(
                children: [
                  Expanded(child: IndexedStack(index: _index, children: pages)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: GlassPanel(
                      borderRadius: 22,
                      child: NavigationBar(
                        selectedIndex: mobileSelected,
                        onDestinationSelected: (value) {
                          setState(() => _index = value == 3 ? _moreIndex : value);
                        },
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
                            icon: Icon(Icons.route_rounded),
                            label: 'Подключение',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.more_horiz_rounded),
                            label: 'Ещё',
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
