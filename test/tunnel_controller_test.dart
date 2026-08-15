import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/mock_tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('controller connects selected imported profile in selected mode',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=reality&sni=example.com&fp=chrome'
      '&pbk=public-key&sid=abcd&type=tcp#Test',
    );

    final controller = TunnelController(
      engine: MockTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    expect(controller.snapshot.status, TunnelStatus.disconnected);
    expect(controller.snapshot.profile?.name, 'Test');
    expect(controller.mode, ConnectionMode.systemProxy);

    await controller.toggle();
    expect(controller.snapshot.status, TunnelStatus.connected);
    expect(controller.snapshot.mode, ConnectionMode.systemProxy);

    await controller.toggle();
    expect(controller.snapshot.status, TunnelStatus.disconnected);
  });

  test('Android defaults to VPN and supports local proxy', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );

    expect(settings.mode, ConnectionMode.vpnTun);
    expect(settings.dnsPreset, DnsPreset.automatic);
    expect(settings.dnsServers, ['1.1.1.1', '8.8.8.8']);
    expect(settings.supportedModes, contains(ConnectionMode.localProxy));
    expect(
        settings.supportedModes, isNot(contains(ConnectionMode.systemProxy)));

    settings.dispose();
  });

  test('connection settings persist proxy, DNS and routing options', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );

    await settings.setSocksPort(31080);
    await settings.setHttpPort(31081);
    await settings.setMtu(1420);
    await settings.setAllowLan(true);
    await settings.setLocalProxyInVpn(false);
    await settings.setBypassPrivateNetworks(false);
    await settings.setSniffingEnabled(false);
    await settings.setLogLevel('info');
    await settings.setCustomDns('9.9.9.9, 149.112.112.112');
    await settings.setDnsPreset(DnsPreset.custom);
    await settings.setStatsIntervalSeconds(5);
    await settings.setShowNotificationSpeed(false);
    await settings.setShowNotificationPing(false);
    await settings.setGeoRoutingEnabled(true);
    await settings.setGeoDirectRules('geoip:private, geosite:ru');
    await settings.setGeoBlockRules('geosite:category-ads-all');
    await settings.setRestartServiceOnKill(false);
    await settings.setCloseToTray(false);

    expect(settings.socksPort, 31080);
    expect(settings.httpPort, 31081);
    expect(settings.mtu, 1420);
    expect(settings.allowLan, isTrue);
    expect(settings.localProxyInVpn, isFalse);
    expect(settings.bypassPrivateNetworks, isFalse);
    expect(settings.sniffingEnabled, isFalse);
    expect(settings.logLevel, 'info');
    expect(settings.dnsServers, ['9.9.9.9', '149.112.112.112']);
    expect(settings.statsIntervalSeconds, 5);
    expect(settings.showNotificationSpeed, isFalse);
    expect(settings.showNotificationPing, isFalse);
    expect(settings.geoRoutingEnabled, isTrue);
    expect(settings.geoDirectRules, ['geoip:private', 'geosite:ru']);
    expect(settings.geoBlockRules, ['geosite:category-ads-all']);
    expect(settings.restartServiceOnKill, isFalse);
    expect(settings.closeToTray, isFalse);

    settings.dispose();
  });

  test('first release defaults stay conservative', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(settings.dispose);

    expect(settings.allowLan, isFalse);
    expect(settings.logLevel, 'error');
    expect(settings.dnsPreset, DnsPreset.automatic);
    expect(settings.localProxyInVpn, isTrue);
    expect(settings.showNotificationPing, isTrue);
    expect(settings.closeToTray, isFalse);
  });

  test('explicit system DNS preference is preserved', () async {
    SharedPreferences.setMockInitialValues({
      'orex_ray_dns_preset_v1': 'system',
    });
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(settings.dispose);

    expect(settings.dnsPreset, DnsPreset.system);
    expect(settings.dnsServers, isEmpty);
  });

  test('Windows closes to tray by default', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(settings.dispose);

    expect(settings.closeToTray, isTrue);
  });

  test('running Android service receives live stats and notification settings',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Test',
    );
    final engine = _RuntimeSettingsEngine();
    final controller = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.connect();
    await settings.setStatsIntervalSeconds(5);
    await settings.setShowNotificationSpeed(false);
    await settings.setShowNotificationPing(false);
    await controller.setStatsUiActive(false);

    expect(
      engine.runtimeSettings,
      contains((interval: 5, speed: false, ping: false)),
    );
    expect(engine.statsUiStates, [false]);
  });

  test('shutdown awaits engine stop and dispose exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final engine = _RecordingTunnelEngine();
    final controller = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.shutdown();
    await controller.shutdown();

    expect(engine.stopCalls, 1);
    expect(engine.disposeCalls, 1);
  });

  test('regular controller disposal does not stop a background tunnel',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final engine = _RecordingTunnelEngine();
    final controller = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
    );

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(engine.stopCalls, 0);
    expect(engine.disposeCalls, 1);
    profiles.dispose();
    settings.dispose();
  });

  test('switching profile while connected restarts the active tunnel',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final first = await profiles.importVlessLink(
      'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@first.example:443'
      '?encryption=none&security=none&type=tcp#First',
    );
    final second = await profiles.createProfile(
      TunnelProfile(
        id: 'second-profile',
        name: 'Second',
        address: 'second.example',
        port: 443,
        userId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ),
    );
    final engine = _RecordingTunnelEngine();
    final controller = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    expect(profiles.selectedTarget?.id, first.id);
    await controller.toggle();
    expect(controller.snapshot.isConnected, isTrue);

    await controller.selectTarget(second.id);

    expect(engine.stopCalls, 1);
    expect(engine.startedTargets, [first.id, second.id]);
    expect(controller.snapshot.isConnected, isTrue);
    expect(controller.snapshot.profile?.id, second.id);
    expect(controller.snapshot.mode, ConnectionMode.vpnTun);
  });

  test('VPN ping uses the active route and never a direct profile socket',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingLatencyProbe(
      const LatencyProbeResult.success(777),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final profile = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Route',
    );
    final routeProbe = _FixedRouteLatencyProbe(
      const LatencyProbeResult.success(123),
    );
    final controller = TunnelController(
      engine: _RecordingTunnelEngine(),
      profiles: profiles,
      settings: settings,
      routeLatencyProbe: routeProbe,
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.setMode(ConnectionMode.vpnTun);
    await controller.connect();
    await controller.refreshSelectedLatency();

    expect(directProbe.calls, 0);
    expect(routeProbe.calls, 1);
    expect(controller.effectiveLatencyFor(controller.snapshot.profile), 123);
    expect(controller.routeLatencyFor(profile.id)?.status, PingStatus.success);
  });

  test(
      'VPN without the parallel local proxy reports no route ping, not TUN TCP',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingLatencyProbe(
      const LatencyProbeResult.success(2),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    await settings.setLocalProxyInVpn(false);
    final profile = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#No-proxy',
    );
    await profiles.updateProfile(
      profile.copyWith(
        latencyMs: 2,
        pingStatus: PingStatus.success,
      ),
    );
    final routeProbe = _FixedRouteLatencyProbe(
      const LatencyProbeResult.success(123),
    );
    final controller = TunnelController(
      engine: _RecordingTunnelEngine(),
      profiles: profiles,
      settings: settings,
      routeLatencyProbe: routeProbe,
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.setMode(ConnectionMode.vpnTun);
    await controller.connect();
    await controller.refreshSelectedLatency();

    expect(directProbe.calls, 0);
    expect(routeProbe.calls, 0);
    expect(controller.effectiveLatencyFor(controller.snapshot.profile), isNull);
    expect(
      controller.effectivePingStatusFor(controller.snapshot.profile),
      PingStatus.unavailable,
    );
    expect(
      controller.routeLatencyFor(profile.id)?.status,
      PingStatus.unavailable,
    );
  });

  test('VPN disconnect performs one direct check after the TUN is down',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingLatencyProbe(
      const LatencyProbeResult.success(87),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final profile = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#After-stop',
    );
    final controller = TunnelController(
      engine: _RecordingTunnelEngine(),
      profiles: profiles,
      settings: settings,
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.setMode(ConnectionMode.vpnTun);
    await controller.connect();
    await controller.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(directProbe.calls, 1);
    expect(profiles.targetById(profile.id)?.latencyMs, 87);
  });

  test('a direct check is discarded if VPN reconnects before it completes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _ControlledLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    await settings.setLocalProxyInVpn(false);
    final profile = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Race',
    );
    final controller = TunnelController(
      engine: _RecordingTunnelEngine(),
      profiles: profiles,
      settings: settings,
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.setMode(ConnectionMode.vpnTun);
    await controller.connect();
    await controller.disconnect();
    await directProbe.started.future;
    await controller.connect();
    directProbe.complete(const LatencyProbeResult.success(2));
    await Future<void>.delayed(Duration.zero);

    expect(directProbe.calls, 1);
    expect(profiles.targetById(profile.id)?.latencyMs, isNull);
    expect(
      profiles.targetById(profile.id)?.pingStatus,
      PingStatus.unknown,
    );
  });

  test('opening the app checks only the selected direct target', () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingLatencyProbe(
      const LatencyProbeResult.success(61),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final profile = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Launch',
    );
    await profiles.createProfile(
      profile.copyWith(
        id: 'unselected',
        name: 'Unselected',
        address: 'second.example.com',
      ),
    );
    final controller = TunnelController(
      engine: _RecordingTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.refreshLatencyOnAppOpen();

    expect(directProbe.calls, 1);
    expect(profiles.targetById(profile.id)?.latencyMs, 61);
    expect(profiles.targetById('unselected')?.latencyMs, isNull);
  });

  test('VPN connection automatically checks the effective route', () async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingLatencyProbe(
      const LatencyProbeResult.success(2),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    await settings.setLocalProxyInVpn(false);
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Auto-route',
    );
    final controller = TunnelController(
      engine: _EventTunnelEngine(),
      profiles: profiles,
      settings: settings,
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await controller.setMode(ConnectionMode.vpnTun);
    await controller.connect();
    await Future<void>.delayed(Duration.zero);

    expect(directProbe.calls, 0);
    expect(
      controller.effectivePingStatusFor(controller.snapshot.profile),
      PingStatus.unavailable,
    );
  });
}

class _RecordingTunnelEngine implements TunnelEngine {
  TunnelSnapshot _current = const TunnelSnapshot(
    status: TunnelStatus.disconnected,
    stats: TrafficStats(),
  );
  final List<String> startedTargets = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => const Stream.empty();

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
      };

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    startedTargets.add(profile.id);
    _current = TunnelSnapshot(
      status: TunnelStatus.connected,
      mode: mode,
      profile: profile,
      stats: const TrafficStats(),
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _current = TunnelSnapshot(
      status: TunnelStatus.disconnected,
      mode: _current.mode,
      profile: _current.profile,
      stats: const TrafficStats(),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

class _RuntimeSettingsEngine extends _RecordingTunnelEngine
    implements TunnelRuntimeSettingsSink, TunnelStatsConsumerSink {
  final List<({int interval, bool speed, bool ping})> runtimeSettings = [];
  final List<bool> statsUiStates = [];

  @override
  Future<void> setStatsUiActive(bool active) async {
    statsUiStates.add(active);
  }

  @override
  Future<void> updateRuntimeSettings({
    required int statsIntervalSeconds,
    required bool showNotificationSpeed,
    required bool showNotificationPing,
  }) async {
    runtimeSettings.add((
      interval: statsIntervalSeconds,
      speed: showNotificationSpeed,
      ping: showNotificationPing,
    ));
  }
}

class _CountingLatencyProbe extends LatencyProbe {
  _CountingLatencyProbe(this.result);

  final LatencyProbeResult result;
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    calls++;
    return result;
  }
}

class _ControlledLatencyProbe extends LatencyProbe {
  final Completer<void> started = Completer<void>();
  final Completer<LatencyProbeResult> _result = Completer<LatencyProbeResult>();
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) {
    calls++;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete(LatencyProbeResult value) => _result.complete(value);
}

class _FixedRouteLatencyProbe extends TunnelRouteLatencyProbe {
  _FixedRouteLatencyProbe(this.result);

  final LatencyProbeResult result;
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure({required int httpPort}) async {
    calls++;
    return result;
  }
}

class _EventTunnelEngine implements TunnelEngine {
  _EventTunnelEngine()
      : _current = const TunnelSnapshot(
          status: TunnelStatus.disconnected,
          stats: TrafficStats(),
        );

  final StreamController<TunnelSnapshot> _events =
      StreamController<TunnelSnapshot>.broadcast();
  TunnelSnapshot _current;

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _events.stream;

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
        ConnectionMode.systemProxy,
      };

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    _emit(
      TunnelSnapshot(
        status: TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        stats: const TrafficStats(),
      ),
    );
    _emit(
      TunnelSnapshot(
        status: TunnelStatus.connected,
        mode: mode,
        profile: profile,
        stats: const TrafficStats(),
      ),
    );
  }

  @override
  Future<void> stop() async {
    _emit(
      _current.copyWith(
        status: TunnelStatus.disconnecting,
        stats: const TrafficStats(),
      ),
    );
    _emit(
      _current.copyWith(
        status: TunnelStatus.disconnected,
        stats: const TrafficStats(),
      ),
    );
  }

  @override
  Future<void> dispose() => _events.close();

  void _emit(TunnelSnapshot value) {
    _current = value;
    _events.add(value);
  }
}
