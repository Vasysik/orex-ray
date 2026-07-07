import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_engine.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/features/connection/connection_screen.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'cancelling a changed proxy port closes the dialog without framework errors',
    (tester) async {
      final harness = await _pumpConnectionScreen(
        tester,
        status: TunnelStatus.disconnected,
      );
      final originalPort = harness.settings.socksPort;

      await tester.tap(find.text('SOCKS5'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '32000');
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.settings.socksPort, originalPort);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'connected VPN visually disables proxy port and MTU rows',
    (tester) async {
      final harness = await _pumpConnectionScreen(
        tester,
        status: TunnelStatus.connected,
      );
      final disabledColor = Theme.of(
        tester.element(find.byType(ConnectionScreen)),
      ).disabledColor;

      _expectDisabledListTile(tester, 'SOCKS5', disabledColor);
      _expectDisabledListTile(tester, 'HTTP', disabledColor);

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      _expectDisabledListTile(tester, 'MTU', disabledColor);

      harness.tunnel.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

Future<_ConnectionHarness> _pumpConnectionScreen(
  WidgetTester tester, {
  required TunnelStatus status,
}) async {
  SharedPreferences.setMockInitialValues({});
  final profiles = await ProfilesController.load();
  final settings = await ConnectionSettingsController.load(
    operatingSystem: 'android',
  );
  final tunnel = TunnelController(
    engine: _StaticTunnelEngine(status),
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
      home: ConnectionScreen(tunnel: tunnel, settings: settings),
    ),
  );
  await tester.pump();

  return _ConnectionHarness(settings: settings, tunnel: tunnel);
}

void _expectDisabledListTile(
  WidgetTester tester,
  String title,
  Color disabledColor,
) {
  final finder = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  expect(finder, findsOneWidget);

  final tile = tester.widget<ListTile>(finder);
  expect(tile.enabled, isFalse);
  expect(tile.onTap, isNull);
  expect(tile.leading, isA<Icon>());
  expect((tile.leading! as Icon).color, disabledColor);
  expect(tile.trailing, isA<Icon>());
  expect((tile.trailing! as Icon).color, disabledColor);
}

class _ConnectionHarness {
  const _ConnectionHarness({required this.settings, required this.tunnel});

  final ConnectionSettingsController settings;
  final TunnelController tunnel;
}

class _StaticTunnelEngine implements TunnelEngine {
  _StaticTunnelEngine(TunnelStatus status)
      : _current = TunnelSnapshot(
          status: status,
          mode: ConnectionMode.vpnTun,
          stats: const TrafficStats(),
        );

  final TunnelSnapshot _current;

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
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
