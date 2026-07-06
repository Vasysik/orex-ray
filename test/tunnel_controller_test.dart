import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/mock_tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('controller connects selected imported profile in selected mode', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
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
    expect(settings.dnsPreset, DnsPreset.system);
    expect(settings.dnsServers, isEmpty);
    expect(settings.supportedModes, contains(ConnectionMode.localProxy));
    expect(settings.supportedModes, isNot(contains(ConnectionMode.systemProxy)));

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
    expect(settings.dnsPreset, DnsPreset.system);
    expect(settings.localProxyInVpn, isTrue);
    expect(settings.showNotificationPing, isTrue);
  });

  test('switching profile while connected restarts the active tunnel', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
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
}

class _RecordingTunnelEngine implements TunnelEngine {
  TunnelSnapshot _current = const TunnelSnapshot(
    status: TunnelStatus.disconnected,
    stats: TrafficStats(),
  );
  final List<String> startedTargets = <String>[];
  int stopCalls = 0;

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
  Future<void> dispose() async {}
}
