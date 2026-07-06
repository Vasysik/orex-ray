import 'package:flutter/material.dart';

import '../../core/apps/app_routing_controller.dart';
import '../../core/geodata/geodata_controller.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/theme_controller.dart';
import '../about/about_screen.dart';
import '../appearance/appearance_screen.dart';
import '../apps/apps_screen.dart';
import '../background/background_screen.dart';
import '../connection/connection_screen.dart';
import '../geodata/geodata_screen.dart';
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
    required this.appRouting,
    required this.geoData,
  });

  final TunnelController tunnel;
  final ProfilesController profiles;
  final ThemeController theme;
  final ConnectionSettingsController settings;
  final AppRoutingController appRouting;
  final GeoDataController geoData;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _appsIndex = 3;
  static const _networkIndex = 4;
  static const _geoDataIndex = 5;
  static const _backgroundIndex = 6;
  static const _appearanceIndex = 7;
  static const _aboutIndex = 8;
  static const _moreIndex = 9;

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(tunnel: widget.tunnel),
      ProfilesScreen(profiles: widget.profiles),
      ConnectionScreen(tunnel: widget.tunnel, settings: widget.settings),
      AppsScreen(controller: widget.appRouting),
      NetworkScreen(settings: widget.settings),
      GeoDataScreen(controller: widget.geoData, settings: widget.settings),
      BackgroundScreen(settings: widget.settings),
      AppearanceScreen(theme: widget.theme),
      const AboutScreen(),
      MoreScreen(
        onOpenApps: () => setState(() => _index = _appsIndex),
        onOpenNetwork: () => setState(() => _index = _networkIndex),
        onOpenGeoData: () => setState(() => _index = _geoDataIndex),
        onOpenBackground: () => setState(() => _index = _backgroundIndex),
        onOpenAppearance: () => setState(() => _index = _appearanceIndex),
        onOpenAbout: () => setState(() => _index = _aboutIndex),
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
                final desktopIndex = _index == _moreIndex ? _networkIndex : _index;
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GlassPanel(
                        borderRadius: 24,
                        child: SizedBox(
                          width: 132,
                          child: NavigationRail(
                            selectedIndex: desktopIndex,
                            onDestinationSelected: (value) =>
                                setState(() => _index = value),
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: -0.85,
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
                                icon: Icon(Icons.apps_rounded),
                                label: Text('Приложения'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.public_rounded),
                                label: Text('Сеть'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.travel_explore_rounded),
                                label: Text('GeoData'),
                              ),
                              NavigationRailDestination(
                                icon: Icon(Icons.battery_saver_rounded),
                                label: Text('Фон'),
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
                            children: pages.take(9).toList(growable: false),
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
