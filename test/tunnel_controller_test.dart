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
}
