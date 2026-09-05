import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/exit_location_refresh_coordinator.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/home_screen.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/widgets/squirrel_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'home shows the empty state without filesystem or platform setup',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final profiles = await ProfilesController.load();
      final settings = await ConnectionSettingsController.load(
        operatingSystem: 'linux',
      );
      final tunnel = TunnelController(
        engine: const _TestTunnelEngine(),
        profiles: profiles,
        settings: settings,
      );
      addTearDown(() {
        tunnel.dispose();
        profiles.dispose();
        settings.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: OrexTheme.dark,
          home: HomeScreen(tunnel: tunnel),
        ),
      );
      await tester.pump();

      expect(find.text('OrexRay'), findsOneWidget);
      // The adaptive header keeps the disconnected status pill whenever it
      // actually fits at this width. Empty state only means there is no
      // selected route; it does not hide the global connection status.
      expect(find.text('Не подключено'), findsOneWidget);
      expect(find.text('Белочка пока без маршрута'), findsOneWidget);
      expect(find.byType(SquirrelMascot), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets('busy ping check keeps the static icon on home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final probe = _PendingHomeLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: probe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Test',
    );
    final tunnel = TunnelController(
      engine: const _TestTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });

    final refresh = tunnel.refreshAllLatencies();
    await tester.pump();
    expect(tunnel.refreshingLatency, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: HomeScreen(tunnel: tunnel),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.network_ping_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    probe.complete(const LatencyProbeResult.success(123));
    await refresh;
  });

  testWidgets('phone layout shows route verification and timeout above button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final profile = await profiles.importVlessLink(
      'vless://33333333-3333-4333-8333-333333333333@example.com:443'
      '?encryption=none&security=none&type=tcp#Mobile-status',
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final engine = _MutableHomeTunnelEngine(
      TunnelSnapshot(
        status: TunnelStatus.connected,
        mode: ConnectionMode.vpnTun,
        profile: TunnelTarget.single(profile),
        stats: const TrafficStats(),
        effectivePingStatus: PingStatus.unknown,
      ),
    );
    final tunnel = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
      egressRefreshPolicy: const ExitLocationRefreshPolicy.disabled(),
      operatingSystem: 'android',
    );
    addTearDown(() {
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: HomeScreen(tunnel: tunnel),
      ),
    );
    await tester.pump();
    expect(find.text('Проверяем маршрут…'), findsOneWidget);

    engine.emit(
      engine.current.copyWith(effectivePingStatus: PingStatus.timeout),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tunnel.effectivePingStatusFor(tunnel.snapshot.profile),
      PingStatus.timeout,
    );
    expect(find.text('Таймаут'), findsOneWidget);
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


class _MutableHomeTunnelEngine implements TunnelEngine {
  _MutableHomeTunnelEngine(this._current);

  final StreamController<TunnelSnapshot> _snapshots =
      StreamController<TunnelSnapshot>.broadcast();
  TunnelSnapshot _current;

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _snapshots.stream;

  @override
  Set<ConnectionMode> get supportedModes => const {ConnectionMode.vpnTun};

  void emit(TunnelSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _snapshots.close();
}

class _PendingHomeLatencyProbe extends LatencyProbe {
  final Completer<LatencyProbeResult> _result = Completer();

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) => _result.future;

  void complete(LatencyProbeResult result) => _result.complete(result);
}
