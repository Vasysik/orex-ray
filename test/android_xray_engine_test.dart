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

  test('forwards notification content choices to a running service', () async {
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
      notificationStatsIntervalSeconds: 30,
      pingIntervalSeconds: 120,
      showNotificationSpeed: false,
      showNotificationPing: false,
    );

    final runtimeSettings = calls.singleWhere(
      (call) => call.method == 'updateRuntimeSettings',
    );
    expect(
      (runtimeSettings.arguments
          as Map<Object?, Object?>)['notificationStatsIntervalSeconds'],
      30,
    );
    expect(
      (runtimeSettings.arguments
          as Map<Object?, Object?>)['showNotificationSpeed'],
      isFalse,
    );
    expect(
      (runtimeSettings.arguments
          as Map<Object?, Object?>)['showNotificationPing'],
      isFalse,
    );
    expect(
      (runtimeSettings.arguments
          as Map<Object?, Object?>)['pingIntervalSeconds'],
      120,
    );
  });

  test('forwards effective route latency and clears a timed-out route',
      () async {
    final calls = <MethodCall>[];
    final target = TunnelTarget.single(
      const TunnelProfile(
        id: 'native-active-target',
        name: 'Native active',
        address: 'active.example',
        port: 443,
        userId: '11111111-1111-4111-8111-111111111111',
        latencyMs: 71,
      ),
    );
    await _mockStatus(
      messenger,
      targetId: target.id,
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
      targetResolver: (id) => id == target.id ? target : null,
    );
    addTearDown(() async {
      await engine.dispose();
      appRouting.dispose();
      settings.dispose();
    });

    await engine.waitForInitialState();
    await engine.updateEffectiveLatency(
      target,
      latencyMs: 321,
      pingStatus: PingStatus.success,
    );
    await engine.updateEffectiveLatency(
      target,
      latencyMs: null,
      pingStatus: PingStatus.timeout,
    );

    final updates = calls
        .where((call) => call.method == 'updateTargetMetadata')
        .map((call) => Map<Object?, Object?>.from(call.arguments as Map))
        .toList(growable: false);
    expect(updates, hasLength(2));
    expect(updates.first['latencyMs'], 321);
    expect(updates.first['pingStatus'], 'success');
    expect(updates.last['latencyMs'], isNull);
    expect(updates.last['pingStatus'], 'timeout');
  });

  test('hydrates native timeout state for the active route', () async {
    final target = TunnelTarget.single(
      const TunnelProfile(
        id: 'native-timeout-target',
        name: 'Native timeout',
        address: 'timeout.example',
        port: 443,
        userId: '11111111-1111-4111-8111-111111111111',
      ),
    );
    await _mockStatus(
      messenger,
      targetId: target.id,
      latencyMs: null,
      pingStatus: 'timeout',
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

    expect(engine.current.effectiveLatencyMs, isNull);
    expect(engine.current.effectivePingStatus, PingStatus.timeout);
  });

  test('does not seed a new route with saved direct TCP latency', () async {
    final calls = <MethodCall>[];
    final target = TunnelTarget.single(
      const TunnelProfile(
        id: 'new-active-target',
        name: 'New active',
        address: 'active.example',
        port: 443,
        userId: '11111111-1111-4111-8111-111111111111',
        latencyMs: 71,
      ),
    );
    await _mockStatus(
      messenger,
      targetId: '',
      status: 'disconnected',
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
    );
    addTearDown(() async {
      await engine.dispose();
      appRouting.dispose();
      settings.dispose();
    });

    await engine.waitForInitialState();
    await engine.start(target, ConnectionMode.vpnTun);

    final start = calls.singleWhere((call) => call.method == 'start');
    expect(
      (start.arguments as Map<Object?, Object?>)['latencyMs'],
      isNull,
    );
  });
}

Future<void> _mockStatus(
  TestDefaultBinaryMessenger messenger, {
  required String targetId,
  String status = 'connected',
  int? latencyMs,
  String? pingStatus,
  Future<Object?> Function(MethodCall call)? onMethodCall,
}) async {
  const channel = MethodChannel('ru.orex.ray/tunnel');
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'status') {
      return <String, dynamic>{
        'status': status,
        'mode': 'vpn_tun',
        'targetId': targetId,
        'downloadBytes': 0,
        'uploadBytes': 0,
        'downloadBytesPerSecond': 0,
        'uploadBytesPerSecond': 0,
        'durationSeconds': 0,
        'latencyMs': latencyMs,
        'pingStatus': pingStatus,
      };
    }
    return onMethodCall?.call(call);
  });
}
