import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/mock_tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('controller connects selected imported profile in selected mode', () async {
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

    expect(controller.snapshot.status, TunnelStatus.disconnected);
    expect(controller.snapshot.profile?.name, 'Test');
    expect(controller.mode, ConnectionMode.systemProxy);

    await controller.toggle();
    expect(controller.snapshot.status, TunnelStatus.connected);
    expect(controller.snapshot.mode, ConnectionMode.systemProxy);

    await controller.toggle();
    expect(controller.snapshot.status, TunnelStatus.disconnected);

    controller.dispose();
    profiles.dispose();
    settings.dispose();
  });

  test('Android defaults to VPN and supports local proxy', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );

    expect(settings.mode, ConnectionMode.vpnTun);
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
    await settings.setBypassPrivateNetworks(false);
    await settings.setSniffingEnabled(false);
    await settings.setLogLevel('info');
    await settings.setCustomDns('9.9.9.9, 149.112.112.112');
    await settings.setDnsPreset(DnsPreset.custom);
    await settings.setStatsIntervalSeconds(5);
    await settings.setShowNotificationSpeed(false);
    await settings.setRestartServiceOnKill(false);

    expect(settings.socksPort, 31080);
    expect(settings.httpPort, 31081);
    expect(settings.mtu, 1420);
    expect(settings.allowLan, isTrue);
    expect(settings.bypassPrivateNetworks, isFalse);
    expect(settings.sniffingEnabled, isFalse);
    expect(settings.logLevel, 'info');
    expect(settings.dnsServers, ['9.9.9.9', '149.112.112.112']);
    expect(settings.statsIntervalSeconds, 5);
    expect(settings.showNotificationSpeed, isFalse);
    expect(settings.restartServiceOnKill, isFalse);

    settings.dispose();
  });

}
