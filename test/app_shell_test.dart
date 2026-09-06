import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/app_version.dart';
import 'package:orex_ray/core/apps/app_routing_controller.dart';
import 'package:orex_ray/core/geodata/geodata_controller.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:orex_ray/features/shell/app_shell.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'mobile back returns to home after a tab and dismisses dialogs first',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final profiles = await ProfilesController.load();
      final settings = await ConnectionSettingsController.load(
        operatingSystem: 'android',
      );
      final theme = await ThemeController.load();
      final appRouting = await AppRoutingController.load();
      final geoData = (await tester.runAsync(
        () => GeoDataController.load(directoryOverride: Directory.current),
      ))!;
      final tunnel = TunnelController(
        engine: const _TestTunnelEngine(),
        profiles: profiles,
        settings: settings,
      );
      addTearDown(() async {
        tunnel.dispose();
        profiles.dispose();
        settings.dispose();
        theme.dispose();
        appRouting.dispose();
        geoData.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: OrexTheme.dark,
          home: AppShell(
            tunnel: tunnel,
            profiles: profiles,
            theme: theme,
            settings: settings,
            appRouting: appRouting,
            geoData: geoData,
            appVersion: OrexAppVersion.fallback,
          ),
        ),
      );
      await tester.pump();

      await _tapMobileTab(tester, 'Профили');
      expect(_mobileNavigationBar(tester).selectedIndex, 1);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_mobileNavigationBar(tester).selectedIndex, 0);

      await _tapMobileTab(tester, 'Подключение');
      expect(_mobileNavigationBar(tester).selectedIndex, 2);
      await tester.tap(find.text('SOCKS5'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(_mobileNavigationBar(tester).selectedIndex, 2);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_mobileNavigationBar(tester).selectedIndex, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
  testWidgets('desktop sidebar hitboxes match their visible fixed rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final theme = await ThemeController.load();
    final appRouting = await AppRoutingController.load();
    final geoData = (await tester.runAsync(
      () => GeoDataController.load(directoryOverride: Directory.current),
    ))!;
    final tunnel = TunnelController(
      engine: const _TestTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() async {
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
      theme.dispose();
      appRouting.dispose();
      geoData.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: AppShell(
          tunnel: tunnel,
          profiles: profiles,
          theme: theme,
          settings: settings,
          appRouting: appRouting,
          geoData: geoData,
          appVersion: OrexAppVersion.fallback,
        ),
      ),
    );
    await tester.pump();

    final home = find.byKey(const ValueKey('desktop-nav-Главная'));
    final profilesNav = find.byKey(const ValueKey('desktop-nav-Профили'));
    expect(home, findsOneWidget);
    expect(profilesNav, findsOneWidget);
    expect(tester.getRect(home).height, 58);
    expect(tester.getRect(profilesNav).height, 58);
    expect(
      tester.getRect(profilesNav).top - tester.getRect(home).bottom,
      4,
    );

    await tester.tap(profilesNav);
    await tester.pump();
    expect(find.text('Серверы, пинг и балансировщики Xray'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

}

Future<void> _tapMobileTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  expect(tab, findsOneWidget);
  await tester.tap(tab);
  await tester.pump();
}

NavigationBar _mobileNavigationBar(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar));

class _TestTunnelEngine implements TunnelEngine {
  const _TestTunnelEngine();

  @override
  TunnelSnapshot get current => const TunnelSnapshot(
        status: TunnelStatus.disconnected,
        stats: TrafficStats(),
      );

  @override
  Stream<TunnelSnapshot> get snapshots => const Stream.empty();

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
      };

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
