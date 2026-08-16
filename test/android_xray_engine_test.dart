import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/apps/app_routing_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/platform/android/android_xray_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tunnelChannel = MethodChannel('ru.orex.ray/tunnel');
  const eventsChannel = MethodChannel('ru.orex.ray/tunnel_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(eventsChannel, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(tunnelChannel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  test('restores a connected Android route by exact target id', () async {
    final target = TunnelTarget.single(
      const TunnelProfile(
        id: 'native-active-target',
        name: 'Native active',
        address: 'active.example',
        port: 443,
        userId: '11111111-1111-4111-8111-111111111111',
      ),
    );
    await _mockStatus(
      messenger,
      targetId: target.id,
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final appRouting = await AppRoutingController.load();
    final engine = AndroidXrayEngine(
      settings: settings,
      appRouting: appRouting,
      targetResolver: (id) => id == target.id ? target : null,
    );
    addTearDown(() async {
      await engine.dispose();
      appRouting.dispose();
      settings.dispose();
    });

    await engine.waitForInitialState();

    expect(engine.current.status, TunnelStatus.connected);
    expect(engine.current.mode, ConnectionMode.vpnTun);
    expect(engine.current.profile?.id, target.id);
  });

  test('never fabricates an Android route when native target id is unknown',
      () async {
    await _mockStatus(messenger, targetId: 'deleted-target');
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final appRouting = await AppRoutingController.load();
    final engine = AndroidXrayEngine(
      settings: settings,
      appRouting: appRouting,
      targetResolver: (_) => null,
    );
    addTearDown(() async {
      await engine.dispose();
      appRouting.dispose();
      settings.dispose();
    });

    await engine.waitForInitialState();

    expect(engine.current.status, TunnelStatus.connected);
    expect(engine.current.profile, isNull);
  });

  test('forwards the notification dismissal choice to a running service',
      () async {
    final calls = <MethodCall>[];
    await _mockStatus(
      messenger,
      targetId: 'native-active-target',
      onMethodCall: (call) async {
        calls.add(call);
        return null;
      },
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final appRouting = await AppRoutingController.load();
    final engine = AndroidXrayEngine(
      settings: settings,
      appRouting: appRouting,
      targetResolver: (_) => null,
    );
    addTearDown(() async {
      await engine.dispose();
      appRouting.dispose();
      settings.dispose();
    });

    await engine.waitForInitialState();
    await engine.updateRuntimeSettings(
      statsIntervalSeconds: 2,
      showNotificationSpeed: true,
      showNotificationPing: true,
      allowNotificationDismissal: true,
    );

    final runtimeSettings = calls.singleWhere(
      (call) => call.method == 'updateRuntimeSettings',
    );
    expect(
      (runtimeSettings.arguments
          as Map<Object?, Object?>)['allowNotificationDismissal'],
      isTrue,
    );
  });
}

Future<void> _mockStatus(
  TestDefaultBinaryMessenger messenger, {
  required String targetId,
  Future<Object?> Function(MethodCall call)? onMethodCall,
}) async {
  const channel = MethodChannel('ru.orex.ray/tunnel');
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'status') {
      return <String, dynamic>{
        'status': 'connected',
        'mode': 'vpn_tun',
        'targetId': targetId,
        'downloadBytes': 0,
        'uploadBytes': 0,
        'downloadBytesPerSecond': 0,
        'uploadBytesPerSecond': 0,
        'durationSeconds': 0,
      };
    }
    return onMethodCall?.call(call);
  });
}
