import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../../core/apps/app_routing_controller.dart';
import '../../core/geodata/geodata_controller.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/theme/theme_controller.dart';
import '../about/about_screen.dart';
import '../appearance/appearance_screen.dart';
import '../apps/apps_screen.dart';
import '../background/background_screen.dart';
import '../connection/connection_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
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
    required this.appVersion,
  });

  final TunnelController tunnel;
  final ProfilesController profiles;
  final ThemeController theme;
  final ConnectionSettingsController settings;
  final AppRoutingController appRouting;
  final GeoDataController geoData;
  final OrexAppVersion appVersion;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _appsIndex = 3;
  static const _networkIndex = 4;
  static const _geoDataIndex = 5;
  static const _backgroundIndex = 6;
  static const _appearanceIndex = 7;
  static const _diagnosticsIndex = 8;
  static const _aboutIndex = 9;
  static const _moreIndex = 10;

  int _index = 0;
  bool _appsPageLoaded = false;

  void _selectPage(int index) {
    if (index == _appsIndex && !_appsPageLoaded) {
      _appsPageLoaded = true;
      unawaited(widget.appRouting.loadApps());
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(tunnel: widget.tunnel),
      ProfilesScreen(profiles: widget.profiles, tunnel: widget.tunnel),
      ConnectionScreen(tunnel: widget.tunnel, settings: widget.settings),
      _appsPageLoaded
          ? AppsScreen(controller: widget.appRouting)
          : const SizedBox.shrink(),
      NetworkScreen(settings: widget.settings),
      GeoDataScreen(controller: widget.geoData, settings: widget.settings),
      BackgroundScreen(settings: widget.settings),
      AppearanceScreen(theme: widget.theme),
      DiagnosticsScreen(
        tunnel: widget.tunnel,
        settings: widget.settings,
        appVersion: widget.appVersion,
      ),
      AboutScreen(appVersion: widget.appVersion),
      MoreScreen(
        showApps: !Platform.isWindows,
        onOpenApps: () => _selectPage(_appsIndex),
        onOpenNetwork: () => _selectPage(_networkIndex),
        onOpenGeoData: () => _selectPage(_geoDataIndex),
        onOpenBackground: () => _selectPage(_backgroundIndex),
        onOpenAppearance: () => _selectPage(_appearanceIndex),
        onOpenDiagnostics: () => _selectPage(_diagnosticsIndex),
        onOpenAbout: () => _selectPage(_aboutIndex),
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
                final desktopPageIndices = Platform.isWindows
                    ? const [0, 1, 2, 4, 5, 6, 7, 8, 9]
                    : const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
                final requestedPageIndex =
                    _index == _moreIndex ? _networkIndex : _index;
                final normalizedPageIndex =
                    desktopPageIndices.contains(requestedPageIndex)
                        ? requestedPageIndex
                        : _networkIndex;
                final desktopIndex =
                    desktopPageIndices.indexOf(normalizedPageIndex);
                final desktopPages = [
                  for (final pageIndex in desktopPageIndices) pages[pageIndex],
                ];
                final desktopDestinations = <NavigationRailDestination>[
                  const NavigationRailDestination(
                    icon: Icon(Icons.power_settings_new_rounded),
                    label: Text('Главная'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.storage_rounded),
                    label: Text('Профили'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.route_rounded),
                    label: Text('Подключение'),
                  ),
                  if (!Platform.isWindows)
                    const NavigationRailDestination(
                      icon: Icon(Icons.apps_rounded),
                      label: Text('Приложения'),
                    ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.public_rounded),
                    label: Text('Сеть'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.travel_explore_rounded),
                    label: Text('GeoData'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.battery_saver_rounded),
                    label: Text('Фон'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.palette_outlined),
                    label: Text('Интерфейс'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.monitor_heart_outlined),
                    label: Text('Диагностика'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.info_outline_rounded),
                    label: Text('О приложении'),
                  ),
                ];
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
                                _selectPage(desktopPageIndices[value]),
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: -0.85,
                            destinations: desktopDestinations,
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
                            children: desktopPages,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final mobileSelected = _index <= 2 ? _index : 3;
              return PopScope(
                canPop: _index == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop || _index == 0) return;
                  _selectPage(0);
                },
                child: Column(
                  children: [
                    Expanded(
                        child: IndexedStack(index: _index, children: pages)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: GlassPanel(
                        borderRadius: 22,
                        child: NavigationBar(
                          selectedIndex: mobileSelected,
                          onDestinationSelected: (value) {
                            _selectPage(value == 3 ? _moreIndex : value);
                          },
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.power_settings_new_rounded),
                              selectedIcon: Icon(
                                Icons.power_settings_new_rounded,
                                color: OrexColors.copper,
                              ),
                              label: 'Главная',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.storage_rounded),
                              selectedIcon: Icon(
                                Icons.storage_rounded,
                                color: OrexColors.copper,
                              ),
                              label: 'Профили',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.route_rounded),
                              selectedIcon: Icon(
                                Icons.route_rounded,
                                color: OrexColors.copper,
                              ),
                              label: 'Подключение',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.more_horiz_rounded),
                              selectedIcon: Icon(
                                Icons.more_horiz_rounded,
                                color: OrexColors.copper,
                              ),
                              label: 'Ещё',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
