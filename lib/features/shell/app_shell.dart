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


class _DesktopNavDestination {
  const _DesktopNavDestination(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _DesktopSideNavigation extends StatelessWidget {
  const _DesktopSideNavigation({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_DesktopNavDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: destinations.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final destination = destinations[index];
        final selected = index == selectedIndex;
        return Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('desktop-nav-${destination.label}'),
              onTap: () => onSelected(index),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: selected
                        ? OrexColors.copper.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        destination.icon,
                        size: 23,
                        color: selected
                            ? OrexColors.copper
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? OrexColors.copper
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
      BackdropGroup(
        child: HomeScreen(tunnel: widget.tunnel, active: _index == 0),
      ),
      BackdropGroup(
        child: ProfilesScreen(profiles: widget.profiles, tunnel: widget.tunnel),
      ),
      BackdropGroup(
        child: ConnectionScreen(tunnel: widget.tunnel, settings: widget.settings),
      ),
      BackdropGroup(
        child: _appsPageLoaded
            ? AppsScreen(controller: widget.appRouting)
            : const SizedBox.shrink(),
      ),
      BackdropGroup(child: NetworkScreen(settings: widget.settings)),
      BackdropGroup(
        child: GeoDataScreen(controller: widget.geoData, settings: widget.settings),
      ),
      BackdropGroup(child: BackgroundScreen(settings: widget.settings)),
      BackdropGroup(child: AppearanceScreen(theme: widget.theme)),
      BackdropGroup(
        child: DiagnosticsScreen(
          tunnel: widget.tunnel,
          settings: widget.settings,
          appVersion: widget.appVersion,
        ),
      ),
      BackdropGroup(
        child: AboutScreen(
          appVersion: widget.appVersion,
          tunnel: widget.tunnel,
        ),
      ),
      BackdropGroup(
        child: MoreScreen(
          showApps: !Platform.isWindows,
          onOpenApps: () => _selectPage(_appsIndex),
          onOpenNetwork: () => _selectPage(_networkIndex),
          onOpenGeoData: () => _selectPage(_geoDataIndex),
          onOpenBackground: () => _selectPage(_backgroundIndex),
          onOpenAppearance: () => _selectPage(_appearanceIndex),
          onOpenDiagnostics: () => _selectPage(_diagnosticsIndex),
          onOpenAbout: () => _selectPage(_aboutIndex),
        ),
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
                final desktopDestinations = <_DesktopNavDestination>[
                  const _DesktopNavDestination(Icons.power_settings_new_rounded, 'Главная'),
                  const _DesktopNavDestination(Icons.storage_rounded, 'Профили'),
                  const _DesktopNavDestination(Icons.route_rounded, 'Подключение'),
                  if (!Platform.isWindows)
                    const _DesktopNavDestination(Icons.apps_rounded, 'Приложения'),
                  const _DesktopNavDestination(Icons.public_rounded, 'Сеть'),
                  const _DesktopNavDestination(Icons.travel_explore_rounded, 'GeoData'),
                  const _DesktopNavDestination(Icons.battery_saver_rounded, 'Фон'),
                  const _DesktopNavDestination(Icons.palette_outlined, 'Интерфейс'),
                  const _DesktopNavDestination(Icons.monitor_heart_outlined, 'Диагностика'),
                  const _DesktopNavDestination(Icons.info_outline_rounded, 'О приложении'),
                ];
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GlassPanel(
                        borderRadius: 24,
                        child: SizedBox(
                          width: 132,
                          child: _DesktopSideNavigation(
                            selectedIndex: desktopIndex,
                            destinations: desktopDestinations,
                            onSelected: (value) =>
                                _selectPage(desktopPageIndices[value]),
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
