import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/app/orex_ray_app.dart';
import 'package:orex_ray/core/apps/app_routing_controller.dart';
import 'package:orex_ray/core/geodata/geodata_controller.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('OrexRay starts with squirrel empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    final profiles = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    final appRouting = await AppRoutingController.load();
    final temp = await Directory.systemTemp.createTemp('orexray_test_geo_');
    final geoData = await GeoDataController.load(directoryOverride: temp);
    addTearDown(() async {
      profiles.dispose();
      settings.dispose();
      appRouting.dispose();
      geoData.dispose();
      theme.dispose();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    await tester.pumpWidget(
      OrexRayApp(
        theme: theme,
        profiles: profiles,
        connectionSettings: settings,
        appRouting: appRouting,
        geoData: geoData,
        tunnelEngine: _TestTunnelEngine(),
      ),
    );
    await tester.pump();

    expect(find.text('OrexRay'), findsOneWidget);
    expect(find.text('Не подключено'), findsNothing);
    expect(find.text('Белочка пока без маршрута'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

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
  Set<ConnectionMode> get supportedModes => const {ConnectionMode.localProxy};

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
