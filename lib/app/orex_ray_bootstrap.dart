import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/apps/app_routing_controller.dart';
import '../core/geodata/geodata_controller.dart';
import '../core/profiles/profiles_controller.dart';
import '../core/settings/connection_settings_controller.dart';
import '../shared/theme/glass.dart';
import '../shared/theme/orex_theme.dart';
import '../shared/theme/theme_controller.dart';
import '../shared/widgets/squirrel_mascot.dart';
import 'orex_ray_app.dart';

class OrexRayBootstrap extends StatefulWidget {
  const OrexRayBootstrap({super.key});

  @override
  State<OrexRayBootstrap> createState() => _OrexRayBootstrapState();
}

class _BootstrapData {
  const _BootstrapData({
    required this.theme,
    required this.profiles,
    required this.settings,
    required this.appRouting,
    required this.geoData,
    required this.appVersion,
  });

  final ThemeController theme;
  final ProfilesController profiles;
  final ConnectionSettingsController settings;
  final AppRoutingController appRouting;
  final GeoDataController geoData;
  final OrexAppVersion appVersion;
}

class _OrexRayBootstrapState extends State<OrexRayBootstrap> {
  late final Future<OrexAppVersion> _versionFuture = OrexAppVersion.load();
  late final Future<_BootstrapData> _future = _initialize();

  Future<_BootstrapData> _initialize() async {
    final minimumSplash =
        Future<void>.delayed(const Duration(milliseconds: 720));
    final geoDataFuture = _versionFuture.then(
      (version) => GeoDataController.load(appVersion: version),
    );
    final results = await Future.wait<Object>([
      ThemeController.load(),
      ProfilesController.load(),
      ConnectionSettingsController.load(),
      AppRoutingController.load(),
      _versionFuture,
      geoDataFuture,
    ]);
    await minimumSplash;
    final appVersion = results[4] as OrexAppVersion;
    final geoData = results[5] as GeoDataController;
    unawaited(geoData.maybeAutoUpdate());
    return _BootstrapData(
      theme: results[0] as ThemeController,
      profiles: results[1] as ProfilesController,
      settings: results[2] as ConnectionSettingsController,
      appRouting: results[3] as AppRoutingController,
      geoData: geoData,
      appVersion: appVersion,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrexAppVersion>(
      future: _versionFuture,
      builder: (context, versionSnapshot) => FutureBuilder<_BootstrapData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootstrapApp(
              child: _StartupError(error: snapshot.error.toString()),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return _BootstrapApp(
              child: OrexRaySplashScreen(
                appVersion: versionSnapshot.data ?? OrexAppVersion.fallback,
              ),
            );
          }
          return OrexRayApp(
            theme: data.theme,
            profiles: data.profiles,
            connectionSettings: data.settings,
            appRouting: data.appRouting,
            geoData: data.geoData,
            appVersion: data.appVersion,
          );
        },
      ),
    );
  }
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: OrexTheme.dark,
      home: child,
    );
  }
}

class OrexRaySplashScreen extends StatelessWidget {
  const OrexRaySplashScreen({
    super.key,
    this.appVersion = OrexAppVersion.fallback,
  });

  final OrexAppVersion appVersion;

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SquirrelMascot(size: 136, caption: 'OrexRay'),
                const SizedBox(height: 14),
                Text(
                  'Защищаем маршрут белочки',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  appVersion.settingsSubtitle,
                  style: const TextStyle(
                    color: OrexColors.cream,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: OrexColors.copper,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: OrexColors.danger,
                  size: 50,
                ),
                const SizedBox(height: 16),
                Text(
                  'OrexRay не удалось запустить',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
