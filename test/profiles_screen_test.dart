import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/exit_location_refresh_coordinator.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/profiles/subscription_source.dart';
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
    expect(find.text('СЕРВЕРЫ'), findsOneWidget);
    expect(find.text('ВЫДЕЛЕНО'), findsOneWidget);
    expect(find.byTooltip('Готово'), findsOneWidget);
    expect(find.byTooltip('Удалить'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Экспорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Копировать массив JSON'));
    await tester.pump();

    expect(clipboardText, isNotNull);
    final decoded = jsonDecode(clipboardText!);
    expect(decoded, isA<List>());
    expect(decoded as List, hasLength(1));
  });

  testWidgets('long press selection exposes bulk actions and direct drag',
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
    await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@example.net:443'
      '?encryption=none&security=none&type=tcp#Bulk-actions-2',
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

    final hold = await tester.startGesture(
      tester.getCenter(find.text('Bulk-actions')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('СЕРВЕРЫ'), findsOneWidget);
    expect(find.text('ВЫДЕЛЕНО'), findsOneWidget);
    expect(find.byTooltip('Готово'), findsOneWidget);
    expect(find.byTooltip('Удалить'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Пинг'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Экспорт'), findsOneWidget);
    expect(find.byTooltip('Удалить'), findsOneWidget);
    expect(find.byTooltip('Выбрать все'), findsOneWidget);
    expect(find.byTooltip('Готово'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(
      find.descendant(
        of: find.byTooltip('Готово'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    final drag = await tester.startGesture(
      tester.getCenter(find.text('Bulk-actions')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await drag.moveBy(const Offset(0, 150));
    await tester.pump(const Duration(milliseconds: 32));
    await drag.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 32));
    await drag.up();
    await tester.pumpAndSettle();
    expect(profiles.profiles.last.name, 'Bulk-actions');

    final selectAllButton = find.byTooltip('Выбрать все');
    final doneButton = find.byTooltip('Готово');
    expect(
      tester.getTopLeft(doneButton).dx,
      greaterThan(tester.getTopLeft(selectAllButton).dx),
    );
  });

  testWidgets('long press on a group selects its profiles and keeps balancers visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    final first = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@one.example:443?encryption=none&security=none&type=tcp#One-group',
    );
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@two.example:443?encryption=none&security=none&type=tcp#Two-group',
    );
    await profiles.setProfilesGroup([first.id, second.id], 'Работа');
    await profiles.saveBalancer(
      name: 'Pool-visible',
      memberIds: [first.id],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
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

    await tester.longPress(find.text('Работа'));
    await tester.pumpAndSettle();

    expect(find.text('ВЫДЕЛЕНО'), findsOneWidget);
    expect(find.text('Pool-visible'), findsOneWidget);
    final checked = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((checkbox) => checkbox.value == true)
        .length;
    expect(checked, greaterThanOrEqualTo(3));
  });

  testWidgets('subscription selection stays separate and exports source URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const subscriptionUrl = 'https://sub.example/user-token';
    const subscribed =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@sub.example:443'
        '?encryption=none&security=none&type=tcp#Subscribed-node';
    final source = _ProfilesSubscriptionSource(
      const SubscriptionFetchResult(
        body: subscribed,
        profileTitle: 'Test subscription',
      ),
    );
    final profiles = await ProfilesController.load(subscriptionSource: source);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@manual.example:443'
      '?encryption=none&security=none&type=tcp#Manual-node',
    );
    await profiles.importSubscription(subscriptionUrl);
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

    await tester.longPress(find.text('Test subscription'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Удалить подписки'), findsOneWidget);
    expect(find.byTooltip('Группа'), findsNothing);
    expect(find.text('Manual-node'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Экспорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скопировать исходную ссылку'));
    await tester.pump();
    expect(clipboardText, subscriptionUrl);

    await tester.tap(find.byTooltip('Готово'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manual-node'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Manual-node'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Группа'), findsOneWidget);
    expect(find.byTooltip('Удалить подписки'), findsNothing);
  });

  testWidgets('subscription keeps raw provider notices beside structured links',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const subscribed = '''
vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@localhost:80?encryption=none&security=none&type=tcp#📅 Осталось: 23 дня
vless://bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb@127.0.0.1:8443?encryption=none&security=none&type=tcp#🟢 Остаток трафика LTE: 80/80GB
vless://cccccccc-cccc-4ccc-8ccc-cccccccccccc@real.example:443?encryption=none&security=none&type=tcp#Real-node
''';
    final source = _ProfilesSubscriptionSource(
      const SubscriptionFetchResult(
        body: subscribed,
        profileTitle: 'Provider subscription',
        supportUrl: 'https://support.example/help',
      ),
    );
    final profiles = await ProfilesController.load(subscriptionSource: source);
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importSubscription('https://sub.example/provider');
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

    expect(
      find.textContaining(
        '📅 Осталось: 23 дня · 🟢 Остаток трафика LTE: 80/80GB',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Поддержка'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('selection actions collapse labels before wrapping',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@compact.example:443'
      '?encryption=none&security=none&type=tcp#Compact-actions',
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
    await tester.longPress(find.text('Compact-actions'));
    await tester.pumpAndSettle();

    expect(find.text('Пинг'), findsNothing);
    expect(find.text('Экспорт'), findsNothing);
    final actionFinders = [
      find.byTooltip('Пинг'),
      find.byTooltip('Экспорт'),
      find.byTooltip('Группа'),
      find.byTooltip('Удалить'),
      find.byTooltip('Выбрать все'),
      find.byTooltip('Готово'),
    ];
    for (final finder in actionFinders) {
      expect(finder, findsOneWidget);
    }
    final top = tester.getTopLeft(actionFinders.first).dy;
    for (final finder in actionFinders.skip(1)) {
      expect(tester.getTopLeft(finder).dy, closeTo(top, 0.5));
    }
  });

  testWidgets('profile tab switches target while VPN is active',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final first = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@first.example:443'
      '?encryption=none&security=none&type=tcp#First-active',
    );
    final second = await profiles.createProfile(
      TunnelProfile(
        id: 'second-active',
        name: 'Second-active',
        address: 'second.example',
        port: 443,
        userId: '22222222-2222-4222-8222-222222222222',
      ),
    );
    await profiles.select(first.id);
    final engine = _MutableProfilesTestTunnelEngine();
    final tunnel = TunnelController(
      engine: engine,
      profiles: profiles,
      settings: settings,
      egressRefreshPolicy: const ExitLocationRefreshPolicy.disabled(),
      routeLatencyProbe: _FixedProfilesRouteLatencyProbe(
        const LatencyProbeResult.unavailable(),
      ),
      routeProbeStartupDelay: Duration.zero,
      operatingSystem: 'android',
    );
    await tunnel.connect();
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

    await tester.tap(find.text(second.name));
    await tester.pump();
    await tester.pump(Duration.zero);

    // The screen owns the gesture/optimistic-selection contract. The full
    // asynchronous STOP -> persistence -> START transaction is covered by
    // tunnel_controller_test.dart where selectTarget() can be awaited
    // directly. A widget onTap callback intentionally does not expose that
    // Future to WidgetTester, so waiting for the whole native transaction
    // here makes this test dependent on fake-async/plugin scheduling.
    expect(profiles.selectedTarget?.id, second.id);
    expect(engine.stopCalls, 1);
    expect(
      find.textContaining('Сменить профиль при активном VPN можно на главном экране'),
      findsNothing,
    );
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
      operatingSystem: 'windows',
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

    // Cancel the Windows desktop ping timer before flutter_test checks for
    // leaked fake timers at the end of the widget test.
    await tunnel.disconnect();
    await tester.pump();
  });
}

class _ProfilesSubscriptionSource extends SubscriptionSource {
  _ProfilesSubscriptionSource(this.response);

  final SubscriptionFetchResult response;

  @override
  Future<SubscriptionFetchResult> loadUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async =>
      response;
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
  int stopCalls = 0;
  final List<String> startedTargets = <String>[];

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
    stopCalls++;
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
