import 'dart:async';

import 'package:flutter/gestures.dart';

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
import 'package:orex_ray/shared/theme/glass.dart';
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
      // The disconnected state may appear in both the header status pill
      // and the connection card; the exact count depends on layout width.
      expect(find.text('Не подключено'), findsWidgets);
      expect(find.text('Белочка пока без маршрута'), findsOneWidget);
      expect(find.byType(SquirrelMascot), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets('home keeps split cards longer and removes redundant mode card',
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

    await tester.binding.setSurfaceSize(const Size(740, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: HomeScreen(tunnel: tunnel),
    ));
    await tester.pumpAndSettle();

    // With 740 logical pixels available, both primary cards remain side by side.
    final hero = find.text('Белочка пока без маршрута');
    final profile = find.text('Нет активного профиля');
    expect(hero, findsOneWidget);
    expect(profile, findsOneWidget);
    expect(tester.getCenter(hero).dx + 100,
        lessThan(tester.getCenter(profile).dx));
    expect(find.text('Текущий режим'), findsNothing);

    // A split layout must form a single rectangle: the connection card on
    // the left is exactly as tall as profile + gap + proxy on the right.
    final heroPanel = find.ancestor(
      of: hero,
      matching: find.byType(GlassPanel),
    );
    final profilePanel = find.ancestor(
      of: profile,
      matching: find.byType(GlassPanel),
    );
    final proxyPanel = find.ancestor(
      of: find.text('Локальный прокси'),
      matching: find.byType(GlassPanel),
    );
    expect(heroPanel, findsOneWidget);
    expect(profilePanel, findsOneWidget);
    expect(proxyPanel, findsOneWidget);
    final leftRect = tester.getRect(heroPanel);
    final upperRightRect = tester.getRect(profilePanel);
    final lowerRightRect = tester.getRect(proxyPanel);
    expect(leftRect.top, closeTo(upperRightRect.top, 0.5));
    expect(leftRect.bottom, closeTo(lowerRightRect.bottom, 0.5));
    expect(
      lowerRightRect.top - upperRightRect.bottom,
      closeTo(16, 0.5),
    );

    // Check the narrowest split width, where the proxy header may wrap.
    // Both columns must still share their top and bottom edges.
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pumpAndSettle();
    final narrowLeft = tester.getRect(heroPanel);
    final narrowTopRight = tester.getRect(profilePanel);
    final narrowBottomRight = tester.getRect(proxyPanel);
    expect(narrowLeft.top, closeTo(narrowTopRight.top, 0.5));
    expect(narrowLeft.bottom, closeTo(narrowBottomRight.bottom, 0.5));
    expect(find.text('Локальный прокси'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(680, 900));
    await tester.pumpAndSettle();
    // The compact layout stacks the two cards and centers both.
    expect((tester.getCenter(hero).dx - tester.getCenter(profile).dx).abs(),
        lessThan(10));
    expect(tester.getCenter(hero).dy, lessThan(tester.getCenter(profile).dy));
    expect(find.text('Текущий режим'), findsNothing);
  });

  testWidgets('home shows accurate local proxy configuration and status',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Proxy-Test',
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
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

    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: HomeScreen(tunnel: tunnel),
    ));
    await tester.pump();

    expect(find.text('Локальный прокси'), findsOneWidget);
    // The proxy has its own glass card, not a section inside profile info.
    final proxyCard = find.ancestor(
      of: find.text('Локальный прокси'),
      matching: find.byType(GlassPanel),
    );
    final profileCard = find.ancestor(
      of: find.text('Протокол'),
      matching: find.byType(GlassPanel),
    );
    expect(proxyCard, findsOneWidget);
    expect(profileCard, findsOneWidget);
    expect(proxyCard.evaluate().single, isNot(same(profileCard.evaluate().single)));
    expect(find.text('Неактивен'), findsOneWidget);
    expect(find.text('SOCKS5 :20808'), findsOneWidget);
    expect(find.text('HTTP :20809'), findsOneWidget);
    expect(find.text('Доступ из локальной сети:'), findsOneWidget);
    expect(find.text('Запрещён'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Запрещён')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(find.textContaining('Нажатие — 127.0.0.1'), findsNothing);

    // Right click offers LAN addresses only when the connection setting
    // explicitly allows LAN access. Localhost remains available.
    await tester.tap(find.text('SOCKS5 :20808'),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('127.0.0.1 · это устройство'), findsOneWidget);
    expect(find.text('Доступ из локальной сети запрещён'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await settings.setSocksPort(20818);
    await tester.pump();
    expect(find.text('SOCKS5 :20818'), findsOneWidget);
    expect(find.text('SOCKS5 :20808'), findsNothing);
  });

  testWidgets('split main cards align with a configured profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Layout-Test',
    );
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
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
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: HomeScreen(tunnel: tunnel),
    ));
    await tester.pumpAndSettle();

    final connection = find.ancestor(
      of: find.text('Готовы подключить Layout-Test'),
      matching: find.byType(GlassPanel),
    );
    final profile = find.ancestor(
      of: find.text('Протокол'),
      matching: find.byType(GlassPanel),
    );
    final proxy = find.ancestor(
      of: find.text('Локальный прокси'),
      matching: find.byType(GlassPanel),
    );
    expect(connection, findsOneWidget);
    expect(profile, findsOneWidget);
    expect(proxy, findsOneWidget);
    expect(tester.getRect(connection).top,
        closeTo(tester.getRect(profile).top, 0.5));
    expect(tester.getRect(connection).bottom,
        closeTo(tester.getRect(proxy).bottom, 0.5));
  });

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
    expect(find.text('Протокол'), findsOneWidget);
    expect(find.text('Транспорт'), findsOneWidget);
    expect(find.text('Задержка'), findsOneWidget);
    expect(find.text('Текущий режим'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    probe.complete(const LatencyProbeResult.success(123));
    await refresh;
  });

  testWidgets('quick profile picker groups profiles and opens current group',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final first = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@one.example:443'
      '?encryption=none&security=none&type=tcp#One',
    );
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@two.example:443'
      '?encryption=none&security=none&type=tcp#Two',
    );
    await profiles.setProfilesGroup([first.id], 'Работа');
    await profiles.setProfilesGroup([second.id], 'Личное');
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

    final currentProfile = find.text('One').first;
    await tester.ensureVisible(currentProfile);
    await tester.pumpAndSettle();
    await tester.tap(currentProfile);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Быстрая смена профиля')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Текущая группа: Работа')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Работа')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Личное')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('One')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Личное')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text('Two')),
      findsOneWidget,
    );
  });

  testWidgets('quick profile picker stays flat without real groups',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@one.example:443'
      '?encryption=none&security=none&type=tcp#Flat-one',
    );
    await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@two.example:443'
      '?encryption=none&security=none&type=tcp#Flat-two',
    );
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

    final currentProfile = find.text('Flat-one').first;
    await tester.ensureVisible(currentProfile);
    await tester.pumpAndSettle();
    await tester.tap(currentProfile);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Flat-one')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Flat-two')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Серверы')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.textContaining('Текущая группа:'),
      ),
      findsNothing,
    );
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
    expect(find.text('Доступен'), findsOneWidget);
    final availableStatus = tester.widget<Text>(find.text('Доступен'));
    expect(availableStatus.style?.color, OrexColors.online);
    expect(availableStatus.style?.fontWeight, FontWeight.w700);

    engine.emit(
      engine.current.copyWith(effectivePingStatus: PingStatus.timeout),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tunnel.effectivePingStatusFor(tunnel.snapshot.profile),
      PingStatus.timeout,
    );
    expect(find.text('Ошибка соединения'), findsOneWidget);
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
