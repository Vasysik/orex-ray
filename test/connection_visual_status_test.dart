import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/shared/theme/connection_visual_status.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/widgets/status_pill.dart';

void main() {
  TunnelSnapshot snapshot(TunnelStatus status) => TunnelSnapshot(
        status: status,
        stats: const TrafficStats(),
      );

  test('badge and native tray share exactly the same color and label', () {
    final states = <(TunnelStatus, PingStatus, String, String, Color)>[
      (TunnelStatus.connected, PingStatus.success,
          'Защищено', 'connected', OrexColors.online),
      (TunnelStatus.connected, PingStatus.unknown,
          'Проверка', 'checking', OrexColors.copper),
      (TunnelStatus.connected, PingStatus.timeout,
          'Нет ответа', 'timeout', OrexColors.danger),
      (TunnelStatus.connected, PingStatus.unavailable,
          'Нет ответа', 'unavailable', OrexColors.danger),
      (TunnelStatus.connecting, PingStatus.unknown,
          'Подключение', 'connecting', OrexColors.copper),
      (TunnelStatus.disconnecting, PingStatus.unknown,
          'Отключение', 'disconnecting', OrexColors.copper),
      (TunnelStatus.error, PingStatus.unknown,
          'Ошибка', 'error', OrexColors.danger),
      (TunnelStatus.disconnected, PingStatus.unknown,
          'Не подключено', 'disconnected', OrexColors.copper),
    ];

    for (final (status, ping, expectedLabel, trayStatus, color) in states) {
      final live = snapshot(status);
      final display = ConnectionVisualStatus.fromSnapshot(live, ping);
      final tray = display.trayArguments(snapshot: live, targetName: 'Example');
      expect(display.label, expectedLabel, reason: '$status/$ping');
      expect(display.color, color, reason: '$status/$ping');
      expect(tray['status'], trayStatus, reason: '$status/$ping');
      expect(tray['label'], display.label);
      expect(tray['colorRgb'], display.color.toARGB32() & 0xFFFFFF);
      expect(tray['markRgb'], OrexColors.cream.toARGB32() & 0xFFFFFF);
      expect(
        display.isProtected,
        status == TunnelStatus.connected && ping == PingStatus.success,
      );
    }
  });

  testWidgets('failure badge uses the exact presentation color',
      (tester) async {
    final presentation = ConnectionVisualStatus.fromSnapshot(
      snapshot(TunnelStatus.connected),
      PingStatus.timeout,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: OrexTheme.dark,
        home: Scaffold(
          body: StatusPill(
            label: presentation.label,
            color: presentation.color,
          ),
        ),
      ),
    );
    final label = tester.widget<Text>(find.text('Нет ответа'));
    expect(label.style?.color, presentation.color);
    final arguments = presentation.trayArguments(
      snapshot: snapshot(TunnelStatus.connected),
      targetName: null,
    );
    expect(
      arguments['colorRgb'],
      label.style!.color!.toARGB32() & 0xFFFFFF,
    );
  });
}
