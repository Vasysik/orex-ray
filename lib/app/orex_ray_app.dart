import 'package:flutter/material.dart';

import '../core/profiles/profiles_controller.dart';
import '../core/settings/connection_settings_controller.dart';
import '../features/home/tunnel_controller.dart';
import '../features/shell/app_shell.dart';
import '../platform/tunnel_engine_factory.dart';
import '../shared/theme/orex_theme.dart';
import '../shared/theme/theme_controller.dart';

class OrexRayApp extends StatefulWidget {
  const OrexRayApp({
    super.key,
    required this.theme,
    required this.profiles,
    required this.connectionSettings,
  });

  final ThemeController theme;
  final ProfilesController profiles;
  final ConnectionSettingsController connectionSettings;

  @override
  State<OrexRayApp> createState() => _OrexRayAppState();
}

class _OrexRayAppState extends State<OrexRayApp> {
  late final TunnelController _tunnel = TunnelController(
    engine: createTunnelEngine(settings: widget.connectionSettings),
    profiles: widget.profiles,
    settings: widget.connectionSettings,
  );

  @override
  void initState() {
    super.initState();
    widget.theme.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.theme.removeListener(_refresh);
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
      ),
    );
  }
}
