import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../../core/update/orexray_updates.dart';
import '../../shared/widgets/orexray_update_dialog.dart';
import '../../core/apps/app_routing_controller.dart';
import '../../core/geodata/geodata_controller.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/theme/theme_controller.dart';
import '../../shared/widgets/responsive_breakpoints.dart';
import '../../shared/widgets/responsive_motion.dart';
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
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: selected
                        ? OrexPalette.of(context).accent.withValues(alpha: 0.14)
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
                            ? OrexPalette.of(context).accent
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? OrexPalette.of(context).accent
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
    this.updates,
  });

  final TunnelController tunnel;
  final ProfilesController profiles;
  final ThemeController theme;
  final ConnectionSettingsController settings;
  final AppRoutingController appRouting;
  final GeoDataController geoData;
  final OrexAppVersion appVersion;
  final OrexRayUpdates? updates;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Android can report an intermediate viewport size on the first Flutter
  // frame. Never paint desktop navigation during that bootstrap frame.
  bool _androidNavigationReady = !Platform.isAndroid;

  // On desktop, keep the departing sidebar mounted for its slide-out when
  // crossing the breakpoint. An initially narrow shell never mounts it.
  bool _hasShownDesktopNavigation = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _androidNavigationReady = true);
      });
    }
  }

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
          updates: widget.updates,
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
      // The content of Android home sits over stationary ambient artwork.
      preblurred: Platform.isAndroid && _index == 0,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >=
                  OrexBreakpoints.shellSideNavigation;
              // The outgoing desktop sidebar is needed only for the Windows
              // resize animation. On Android, never leave a hidden sidebar
              // over the mobile UI (including while the viewport settles).
              final showDesktopSidebar = desktop
                  ? _androidNavigationReady
                  : !Platform.isAndroid && _hasShownDesktopNavigation;
              if (showDesktopSidebar && desktop) {
                _hasShownDesktopNavigation = true;
              }
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
              final desktopDestinations = <_DesktopNavDestination>[
                const _DesktopNavDestination(
                  Icons.power_settings_new_rounded,
                  'Главная',
                ),
                const _DesktopNavDestination(Icons.storage_rounded, 'Профили'),
                const _DesktopNavDestination(
                  Icons.route_rounded,
                  'Подключение',
                ),
                if (!Platform.isWindows)
                  const _DesktopNavDestination(
                    Icons.apps_rounded,
                    'Приложения',
                  ),
                const _DesktopNavDestination(Icons.public_rounded, 'Сеть'),
                const _DesktopNavDestination(
                  Icons.travel_explore_rounded,
                  'GeoData',
                ),
                const _DesktopNavDestination(
                  Icons.battery_saver_rounded,
                  'Фон',
                ),
                const _DesktopNavDestination(
                  Icons.palette_outlined,
                  'Интерфейс',
                ),
                const _DesktopNavDestination(
                  Icons.monitor_heart_outlined,
                  'Диагностика',
                ),
                const _DesktopNavDestination(
                  Icons.info_outline_rounded,
                  'О приложении',
                ),
              ];
              final mobileSelected = _index <= 2 ? _index : 3;
              final visiblePageIndex = desktop ? normalizedPageIndex : _index;
              final pageStack = IndexedStack(
                index: visiblePageIndex,
                children: pages,
              );
              final content = OrexResponsiveReveal(
                layoutKey: desktop
                    ? 'shell-desktop-content'
                    : 'shell-mobile-content',
                child: desktop
                    ? GlassPanel(
                        borderRadius: 24,
                        opacity: 0.30,
                        child: pageStack,
                      )
                    : pageStack,
              );
              final navigationDuration =
                  OrexMotion.duration(context, OrexMotion.navigation);

              return PopScope(
                canPop: desktop || _index == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (desktop || didPop || _index == 0) return;
                  _selectPage(0);
                },
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    AnimatedPadding(
                      duration: navigationDuration,
                      curve: OrexMotion.curve,
                      padding: desktop
                          ? const EdgeInsets.fromLTRB(156, 12, 12, 12)
                          : const EdgeInsets.fromLTRB(0, 0, 0, 90),
                      child: content,
                    ),
                    if (widget.updates != null)
                      Positioned(
                        top: 8, left: desktop ? 164 : 12, right: 12,
                        child: AnimatedBuilder(
                        animation: widget.updates!,
                        builder: (context, _) {
                          final updates = widget.updates!;
                          if (!updates.showBanner) return const SizedBox.shrink();
                          return Material(
                              elevation: 6,
                              color: OrexPalette.of(context).surface,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                key: const ValueKey('orexray-update-banner'),
                                leading: Icon(Icons.system_update_rounded, color: OrexPalette.of(context).accent),
                                title: const Text('Доступна новая версия OrexRay'),
                                subtitle: Text('Версия ${updates.available!.tag} · GitHub Releases'),
                                onTap: () => showOrexRayUpdateDialog(context, updates),
                                trailing: IconButton(
                                  tooltip: 'Скрыть уведомление',
                                  onPressed: updates.dismiss,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                          );
                        },
                      ),
                      ),
                    if (showDesktopSidebar)
                      Positioned(
                        left: 12,
                        top: 12,
                        bottom: 12,
                        width: 132,
                        child: ExcludeSemantics(
                        excluding: !desktop,
                        child: IgnorePointer(
                          ignoring: !desktop,
                          child: AnimatedSlide(
                            duration: navigationDuration,
                            curve: OrexMotion.curve,
                            offset: desktop
                                ? Offset.zero
                                : const Offset(-1.16, 0),
                            child: AnimatedOpacity(
                              duration: navigationDuration,
                              curve: OrexMotion.curve,
                              opacity: desktop ? 1 : 0,
                              child: GlassPanel(
                                key: const ValueKey(
                                  'desktop-side-navigation-panel',
                                ),
                                borderRadius: 24,
                                child: _DesktopSideNavigation(
                                  selectedIndex: desktopIndex,
                                  destinations: desktopDestinations,
                                  onSelected: (value) => _selectPage(
                                    desktopPageIndices[value],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: ExcludeSemantics(
                        excluding: desktop,
                        child: IgnorePointer(
                          ignoring: desktop,
                          child: AnimatedSlide(
                            duration: navigationDuration,
                            curve: OrexMotion.curve,
                            offset: desktop
                                ? const Offset(0, 1.18)
                                : Offset.zero,
                            child: AnimatedOpacity(
                              duration: navigationDuration,
                              curve: OrexMotion.curve,
                              opacity: desktop ? 0 : 1,
                              child: GlassPanel(
                                key: const ValueKey(
                                  'mobile-bottom-navigation-panel',
                                ),
                                borderRadius: 22,
                                child: NavigationBar(
                                  selectedIndex: mobileSelected,
                                  onDestinationSelected: (value) {
                                    _selectPage(
                                      value == 3 ? _moreIndex : value,
                                    );
                                  },
                                  destinations: [
                                    NavigationDestination(
                                      icon: Icon(
                                        Icons.power_settings_new_rounded,
                                      ),
                                      selectedIcon: Icon(
                                        Icons.power_settings_new_rounded,
                                        color: OrexPalette.of(context).accent,
                                      ),
                                      label: 'Главная',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.storage_rounded),
                                      selectedIcon: Icon(
                                        Icons.storage_rounded,
                                        color: OrexPalette.of(context).accent,
                                      ),
                                      label: 'Профили',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.route_rounded),
                                      selectedIcon: Icon(
                                        Icons.route_rounded,
                                        color: OrexPalette.of(context).accent,
                                      ),
                                      label: 'Подключение',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.more_horiz_rounded),
                                      selectedIcon: Icon(
                                        Icons.more_horiz_rounded,
                                        color: OrexPalette.of(context).accent,
                                      ),
                                      label: 'Ещё',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
