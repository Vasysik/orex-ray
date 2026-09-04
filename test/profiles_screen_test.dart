import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/exit_location_refresh_coordinator.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:orex_ray/features/profiles/profiles_screen.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('manual profile form selects every supported outbound protocol',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
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
        home: ProfilesScreen(profiles: profiles, tunnel: tunnel),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый профиль'));
    await tester.pumpAndSettle();

    expect(find.text('Протокол'), findsOneWidget);
    final selector = find.byType(DropdownButtonFormField<OutboundProtocol>);
    expect(selector, findsOneWidget);

    await tester.tap(selector);
    await tester.pumpAndSettle();
    for (final protocol in OutboundProtocol.values) {
      expect(find.text(protocol.title), findsWidgets);
    }

    await tester.tap(find.text('SOCKS5').last);
    await tester.pumpAndSettle();

    expect(find.text('Имя пользователя (необязательно)'), findsOneWidget);
    expect(find.text('Пароль (необязательно)'), findsOneWidget);
  });

  testWidgets('copies selected Xray profiles as a JSON array', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@copy-all.example:443'
      '?encryption=none&security=none&type=tcp#Copy-all',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? clipboardText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: ProfilesScreen(profiles: profiles, tunnel: tunnel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Copy-all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ВЫДЕЛЕНО 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Экспортировать выбранные'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Копировать массив JSON'));
    await tester.pump();

    expect(clipboardText, isNotNull);
    final decoded = jsonDecode(clipboardText!);
    expect(decoded, isA<List>());
    expect(decoded as List, hasLength(1));
  });

  testWidgets('long press selection exposes bulk actions and reorder mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Bulk-actions',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
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
        home: Scaffold(
          body: ProfilesScreen(profiles: profiles, tunnel: tunnel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Bulk-actions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ВЫДЕЛЕНО 1'), findsOneWidget);
    expect(find.byTooltip('Проверить пинг выбранных'), findsOneWidget);
    expect(find.byTooltip('Экспортировать выбранные'), findsOneWidget);
    expect(find.byTooltip('Удалить выбранные'), findsOneWidget);

    await tester.tap(find.byTooltip('Изменить порядок'));
    await tester.pumpAndSettle();
    expect(find.text('Порядок серверов'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
  });

  testWidgets('create menu no longer contains profile export', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
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
        home: Scaffold(
          body: ProfilesScreen(profiles: profiles, tunnel: tunnel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Экспорт JSON Xray'), findsNothing);
  });

  testWidgets('copies one profile as a single Xray JSON object', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@copy-one.example:443'
      '?encryption=none&security=none&type=tcp#Copy-one',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? clipboardText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: ProfilesScreen(profiles: profiles, tunnel: tunnel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Экспорт JSON Xray'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Копировать JSON'));
    await tester.pump();

    expect(clipboardText, isNotNull);
    final decoded = jsonDecode(clipboardText!);
    expect(decoded, isA<Map>());
    expect((decoded as Map)['outbounds'], isA<List>());
  });

  testWidgets('busy ping check keeps the static icon in profiles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final probe = _PendingProfilesLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: probe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Test',
    );
    final tunnel = TunnelController(
      engine: const _ProfilesTestTunnelEngine(),
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
        home: ProfilesScreen(profiles: profiles, tunnel: tunnel),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.network_ping_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    probe.complete(const LatencyProbeResult.success(123));
    await refresh;
  });

  testWidgets(
      'active VPN list keeps saved direct pings and disables other refreshes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directProbe = _CountingProfilesLatencyProbe(
      const LatencyProbeResult.success(600),
    );
    final profiles = await ProfilesController.load(latencyProbe: directProbe);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final active = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@active.example:443'
      '?encryption=none&security=none&type=tcp#Active',
    );
    await profiles.refreshLatency(active.id);
    final inactive = await profiles.createProfile(
      const TunnelProfile(
        id: 'inactive-profile',
        name: 'Inactive',
        address: 'inactive.example',
        port: 443,
        userId: '22222222-2222-4222-8222-222222222222',
        latencyMs: 1000,
        pingStatus: PingStatus.success,
      ),
    );
    final balancer = await profiles.saveBalancer(
      name: 'Pool',
      memberIds: [active.id, inactive.id],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
    );
    final tunnel = TunnelController(
      engine: _MutableProfilesTestTunnelEngine(),
      profiles: profiles,
      settings: settings,
      egressRefreshPolicy: const ExitLocationRefreshPolicy.disabled(),
      routeLatencyProbe: _FixedProfilesRouteLatencyProbe(
        const LatencyProbeResult.success(123),
      ),
      routeProbeStartupDelay: Duration.zero,
    );
    addTearDown(() {
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });

    await tunnel.setMode(ConnectionMode.vpnTun);
    await tunnel.connect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tunnel.refreshSelectedLatency();

    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: ProfilesScreen(profiles: profiles, tunnel: tunnel),
      ),
    );
    await tester.pump();

    expect(find.text('123 мс'), findsNothing);
    expect(find.text('600 мс'), findsNWidgets(2));
    expect(find.text('1000 мс'), findsOneWidget);
    for (final text in tester.widgetList<Text>(find.text('600 мс'))) {
      expect(text.style?.color, OrexColors.copper);
    }
    expect(
      tester.widget<Text>(find.text('1000 мс')).style?.color,
      OrexColors.danger,
    );
    expect(tunnel.canRefreshTargetLatency(active.id), isTrue);
    expect(tunnel.canRefreshTargetLatency(inactive.id), isFalse);
    expect(tunnel.canRefreshTargetLatency(balancer.id), isFalse);

    await tunnel.refreshProfileLatency(inactive.id);
    expect(directProbe.calls, 1);
  });
}

class _CountingProfilesLatencyProbe extends LatencyProbe {
  _CountingProfilesLatencyProbe(this.result);

  final LatencyProbeResult result;
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    calls++;
    return result;
  }
}

class _PendingProfilesLatencyProbe extends LatencyProbe {
  final Completer<LatencyProbeResult> _result = Completer();

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) => _result.future;

  void complete(LatencyProbeResult result) => _result.complete(result);
}

class _FixedProfilesRouteLatencyProbe extends TunnelRouteLatencyProbe {
  _FixedProfilesRouteLatencyProbe(this.result);

  final LatencyProbeResult result;

  @override
  Future<LatencyProbeResult> measure({
    required int httpPort,
    Uri? probeUri,
  }) async =>
      result;
}

class _ProfilesTestTunnelEngine implements TunnelEngine {
  const _ProfilesTestTunnelEngine();

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

class _MutableProfilesTestTunnelEngine implements TunnelEngine {
  TunnelSnapshot _current = const TunnelSnapshot(
    status: TunnelStatus.disconnected,
    stats: TrafficStats(),
  );

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => const Stream.empty();

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
        ConnectionMode.systemProxy,
      };

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    _current = TunnelSnapshot(
      status: TunnelStatus.connected,
      mode: mode,
      profile: profile,
      stats: const TrafficStats(),
    );
  }

  @override
  Future<void> stop() async {
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
