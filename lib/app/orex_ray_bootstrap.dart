import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_version.dart';
import '../core/apps/app_routing_controller.dart';
import '../core/geodata/geodata_controller.dart';
import '../core/profiles/latency_probe.dart';
import '../core/profiles/profiles_controller.dart';
import '../core/settings/connection_settings_controller.dart';
import '../platform/windows/windows_direct_latency_probe.dart';
import '../platform/windows/windows_elevation_controller.dart';
import '../shared/theme/glass.dart';
import '../shared/theme/orex_palette.dart';
import '../shared/theme/orex_theme.dart';
import '../shared/theme/theme_controller.dart';
import '../shared/l10n/orex_l10n.dart';
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
  // The theme loads on its own fast path so the splash window can repaint in
  // the user's colors long before the heavier controllers are ready.
  late final Future<ThemeController> _themeFuture = _loadTheme();
  late final Future<OrexAppVersion> _versionFuture = OrexAppVersion.load();
  late final Future<_BootstrapData> _future = _initialize();

  bool _shellPainted = false;

  Future<ThemeController> _loadTheme() async {
    final theme = await ThemeController.load();
    try {
      await theme.ensureDefaultBuiltin();
    } on Object {
      // A missing preset asset must never block startup; the palette
      // fallbacks keep the app fully usable.
    }
    return theme;
  }

  Future<_BootstrapData> _initialize() async {
    final minimumSplash =
        Future<void>.delayed(const Duration(milliseconds: 720));
    final geoDataFuture = _versionFuture.then(
      (version) => GeoDataController.load(appVersion: version),
    );
    // Android excludes the OrexRay UID from its VpnService, so the regular
    // socket is outside the TUN. Windows needs a native, interface-bound
    // socket instead; other platforms keep direct checks disabled in a VPN.
    final latencyProbe = Platform.isWindows
        ? WindowsDirectLatencyProbe()
        : LatencyProbe(canMeasureWhileVpnActive: Platform.isAndroid);
    final results = await Future.wait<Object>([
      _themeFuture,
      ProfilesController.load(latencyProbe: latencyProbe),
      ConnectionSettingsController.load(),
      AppRoutingController.load(),
      _versionFuture,
      geoDataFuture,
      OrexL10n.load(),
    ]);
    final settings = results[2] as ConnectionSettingsController;
    if (Platform.isWindows &&
        await WindowsElevationController.maybeRestartOnStartup(
          enabled: settings.windowsRunAsAdministrator,
        )) {
      exit(0);
    }

    await minimumSplash;
    final appVersion = results[4] as OrexAppVersion;
    final geoData = results[5] as GeoDataController;
    unawaited(geoData.maybeAutoUpdate());
    return _BootstrapData(
      theme: results[0] as ThemeController,
      profiles: results[1] as ProfilesController,
      settings: settings,
      appRouting: results[3] as AppRoutingController,
      geoData: geoData,
      appVersion: appVersion,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrexAppVersion>(
      future: _versionFuture,
      builder: (context, versionSnapshot) => FutureBuilder<ThemeController>(
        future: _themeFuture,
        builder: (context, themeSnapshot) =>
            FutureBuilder<_BootstrapData>(
          future: _future,
          builder: (context, snapshot) {
            final splash = _BootstrapApp(
              theme: themeSnapshot.data,
              child: OrexRaySplashScreen(
                appVersion: versionSnapshot.data ?? OrexAppVersion.fallback,
              ),
            );
            if (snapshot.hasError) {
              return _BootstrapApp(
                theme: themeSnapshot.data,
                child: _StartupError(error: snapshot.error.toString()),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return splash;
            }
            // Keep the splash over the real UI until the shell has painted
            // its first frames. This hides the viewport settle and the lazy
            // page warm-up instead of flashing half-built interface elements.
            // The Directionality wrapper is required: this Stack sits above
            // the inner MaterialApp, so without it the default
            // AlignmentDirectional alignment has no text direction and the
            // root render object throws on every layout pass.
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OrexRayApp(
                    theme: data.theme,
                    profiles: data.profiles,
                    connectionSettings: data.settings,
                    appRouting: data.appRouting,
                    geoData: data.geoData,
                    appVersion: data.appVersion,
                    onFirstFrame: _handleFirstFrame,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _shellPainted
                        ? const SizedBox.shrink()
                        : IgnorePointer(child: splash),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleFirstFrame() {
    if (!mounted || _shellPainted) return;
    setState(() => _shellPainted = true);
  }
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({this.theme, required this.child});

  /// Colors of the default built-in preset, used only for the few frames
  /// before SharedPreferences answers. Keeping them in sync with the gray
  /// default avoids a brown-to-gray flash on fresh installs.
  static const fallbackColors = <String, Color>{
    'accent': Color(0xFFCB8552),
    'secondary': Color(0xFFA46742),
    'background': Color(0xFF202020),
    'surface': Color(0xFF2B2B2B),
    'text': Color(0xFFF5F5F5),
    'mutedText': Color(0xFFB8B8B8),
    'border': Color(0xFF454545),
    'success': Color(0xFF6CCB75),
    'danger': Color(0xFFFF7373),
  };

  /// When the theme controller is already loaded, the splash repaints in the
  /// user's colors instead of a fixed launch look.
  final ThemeController? theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final activeTheme = theme?.activeTheme;
    final brightness = activeTheme?.light == true
        ? Brightness.light
        : Brightness.dark;
    final colors = theme?.colors ?? fallbackColors;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: OrexTheme.withColors(brightness, colors).copyWith(
        extensions: [OrexPalette.resolve(brightness, colors)],
      ),
      home: child,
      locale: OrexL10n.instanceOrNull?.locale,
      supportedLocales: OrexL10n.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
                  'Guarding the squirrel\'s route'.tr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  appVersion.settingsSubtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Theme.of(context).colorScheme.primary,
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
                  'OrexRay failed to start'.tr,
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
