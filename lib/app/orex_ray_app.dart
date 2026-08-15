import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/apps/app_routing_controller.dart';
import '../core/geodata/geodata_controller.dart';
import '../core/profiles/profiles_controller.dart';
import '../core/settings/connection_settings_controller.dart';
import '../core/tunnel/tunnel_engine.dart';
import '../features/home/tunnel_controller.dart';
import '../features/shell/app_shell.dart';
import '../platform/tunnel_engine_factory.dart';
import '../platform/android/android_startup_controller.dart';
import '../platform/windows/windows_lifecycle_controller.dart';
import '../shared/theme/orex_theme.dart';
import '../shared/theme/theme_controller.dart';

class OrexRayApp extends StatefulWidget {
  const OrexRayApp({
    super.key,
    required this.theme,
    required this.profiles,
    required this.connectionSettings,
    required this.appRouting,
    required this.geoData,
    this.appVersion = OrexAppVersion.fallback,
    this.tunnelEngine,
  });

  final ThemeController theme;
  final ProfilesController profiles;
  final ConnectionSettingsController connectionSettings;
  final AppRoutingController appRouting;
  final GeoDataController geoData;
  final OrexAppVersion appVersion;
  final TunnelEngine? tunnelEngine;

  @override
  State<OrexRayApp> createState() => _OrexRayAppState();
}

class _OrexRayAppState extends State<OrexRayApp> with WidgetsBindingObserver {
  late final TunnelController _tunnel = TunnelController(
    engine: widget.tunnelEngine ??
        createTunnelEngine(
          settings: widget.connectionSettings,
          appRouting: widget.appRouting,
          appVersion: widget.appVersion,
        ),
    profiles: widget.profiles,
    settings: widget.connectionSettings,
  );
  WindowsLifecycleController? _windowsLifecycle;
  bool? _lastAndroidBootSetting;
  bool? _lastStatsUiActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.theme.addListener(_refresh);
    widget.connectionSettings.addListener(_syncPlatformStartupSettings);
    if (Platform.isWindows) {
      _windowsLifecycle = WindowsLifecycleController(
        tunnel: _tunnel,
        settings: widget.connectionSettings,
      );
      unawaited(_windowsLifecycle!.initialize());
    }
    _syncPlatformStartupSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncStatsUiActivity(WidgetsBinding.instance.lifecycleState);
      // One event-driven reachability check for the currently selected target.
      // A VPN that is already running uses its effective Xray route instead of
      // opening a direct socket through the TUN.
      unawaited(_tunnel.refreshLatencyOnAppOpen());
      if (widget.connectionSettings.autoConnectOnStartup &&
          _tunnel.selectedProfile != null) {
        unawaited(Future<void>.delayed(
          const Duration(milliseconds: 450),
          _tunnel.connect,
        ));
      }
    });
  }

  void _syncPlatformStartupSettings() {
    if (!Platform.isAndroid) return;
    final enabled = widget.connectionSettings.autoConnectOnStartup;
    if (_lastAndroidBootSetting == enabled) return;
    _lastAndroidBootSetting = enabled;
    unawaited(
      AndroidStartupController.setAutoConnectOnBoot(enabled).catchError((_) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncStatsUiActivity(state);
  }

  void _syncStatsUiActivity(AppLifecycleState? state) {
    if (!Platform.isAndroid) return;
    final active = state == null || state == AppLifecycleState.resumed;
    if (_lastStatsUiActive == active) return;
    _lastStatsUiActive = active;
    unawaited(_tunnel.setStatsUiActive(active));
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.theme.removeListener(_refresh);
    widget.connectionSettings.removeListener(_syncPlatformStartupSettings);
    _windowsLifecycle?.dispose();
    _tunnel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OrexRay',
      theme: OrexTheme.light,
      darkTheme: OrexTheme.dark,
      themeMode: widget.theme.mode,
      home: AppShell(
        tunnel: _tunnel,
        profiles: widget.profiles,
        theme: widget.theme,
        settings: widget.connectionSettings,
        appRouting: widget.appRouting,
        geoData: widget.geoData,
        appVersion: widget.appVersion,
      ),
    );
  }
}
