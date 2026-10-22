import 'package:flutter/material.dart';

import '../../core/tunnel/tunnel_models.dart';
import 'orex_theme.dart';

/// One presentation contract for the connection badge and the Windows tray.
/// Ping here must be the *active route* status, not a stored direct server ping.
class ConnectionVisualStatus {
  const ConnectionVisualStatus._({
    required this.label,
    required this.color,
    required this.isProtected,
    required this.trayStatus,
  });

  final String label;
  final Color color;
  final bool isProtected;
  final String trayStatus;

  static bool isRouteFailed(PingStatus status) =>
      status == PingStatus.timeout || status == PingStatus.unavailable;

  factory ConnectionVisualStatus.fromSnapshot(
    TunnelSnapshot snapshot,
    PingStatus routePingStatus,
  ) {
    if (snapshot.isConnected) {
      if (isRouteFailed(routePingStatus)) {
        return ConnectionVisualStatus._(
          label: 'Нет ответа',
          color: OrexColors.danger,
          isProtected: false,
          trayStatus: routePingStatus == PingStatus.timeout
              ? 'timeout'
              : 'unavailable',
        );
      }
      if (routePingStatus == PingStatus.success) {
        return const ConnectionVisualStatus._(
          label: 'Защищено',
          color: OrexColors.online,
          isProtected: true,
          trayStatus: 'connected',
        );
      }
      return const ConnectionVisualStatus._(
        label: 'Проверка',
        color: OrexColors.copper,
        isProtected: false,
        trayStatus: 'checking',
      );
    }
    return switch (snapshot.status) {
      TunnelStatus.connecting => const ConnectionVisualStatus._(
          label: 'Подключение',
          color: OrexColors.copper,
          isProtected: false,
          trayStatus: 'connecting',
        ),
      TunnelStatus.disconnecting => const ConnectionVisualStatus._(
          label: 'Отключение',
          color: OrexColors.copper,
          isProtected: false,
          trayStatus: 'disconnecting',
        ),
      TunnelStatus.error => const ConnectionVisualStatus._(
          label: 'Ошибка',
          color: OrexColors.danger,
          isProtected: false,
          trayStatus: 'error',
        ),
      _ => const ConnectionVisualStatus._(
          label: 'Не подключено',
          color: OrexColors.copper,
          isProtected: false,
          trayStatus: 'disconnected',
        ),
    };
  }

  /// Native tray receives the exact same RGB as the Flutter status badge.
  /// C++ only draws the icon; it must not own a second status-color palette.
  Map<String, Object?> trayArguments({
    required TunnelSnapshot snapshot,
    required String? targetName,
  }) => <String, Object?>{
        'status': trayStatus,
        'label': label,
        'colorRgb': color.toARGB32() & 0xFFFFFF,
        'markRgb': OrexColors.cream.toARGB32() & 0xFFFFFF,
        'targetName': targetName,
        'canDisconnect': snapshot.status == TunnelStatus.connected ||
            snapshot.status == TunnelStatus.connecting ||
            snapshot.status == TunnelStatus.error,
      };
}
