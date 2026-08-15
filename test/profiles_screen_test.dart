import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
