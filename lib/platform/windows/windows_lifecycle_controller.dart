import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../features/home/tunnel_controller.dart';

class WindowsLifecycleController {
  WindowsLifecycleController({
    required TunnelController tunnel,
    required ConnectionSettingsController settings,
  })  : _tunnel = tunnel,
        _settings = settings;

  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');

  final TunnelController _tunnel;
  final ConnectionSettingsController _settings;
  bool _initialized = false;
  bool _exitInProgress = false;
  String? _lastTrayState;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    _settings.addListener(_onSettingsChanged);
    _tunnel.addListener(_onTunnelChanged);
    await _syncCloseBehavior();
    await _syncTrayStatus();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'requestExit':
        await _shutdownAndExit();
        return;
      case 'trayDisconnect':
        await _tunnel.disconnect();
        return;
      default:
        throw MissingPluginException(
          'Unknown Windows lifecycle method: ${call.method}',
        );
    }
  }

  void _onSettingsChanged() {
    unawaited(_syncCloseBehavior());
  }

  void _onTunnelChanged() {
    unawaited(_syncTrayStatus());
  }

  Future<void> _shutdownAndExit() async {
    if (_exitInProgress) return;
    _exitInProgress = true;

    final snapshot = _tunnel.snapshot;
    if (snapshot.status != TunnelStatus.disconnected) {
      try {
        await _channel.invokeMethod<void>('updateTray', {
          'status': TunnelStatus.disconnecting.name,
          'targetName': snapshot.profile?.name.trim(),
          'canDisconnect': false,
        });
      } catch (_) {
        // Exit cleanup still has to run even if Explorer or the tray channel is
        // temporarily unavailable.
      }
    }

    try {
      await _tunnel.shutdown();
    } finally {
      await _channel.invokeMethod<void>('completeExit');
    }
  }

  Future<void> _syncCloseBehavior() async {
    await _channel.invokeMethod<void>('setCloseToTray', _settings.closeToTray);
  }

  Future<void> _syncTrayStatus() async {
    final snapshot = _tunnel.snapshot;
    final targetName = snapshot.profile?.name.trim();
    final stateKey = '${snapshot.status.name}|${targetName ?? ''}';
    if (_lastTrayState == stateKey) return;
    _lastTrayState = stateKey;

    await _channel.invokeMethod<void>('updateTray', {
      'status': snapshot.status.name,
      'targetName': targetName,
      'canDisconnect': snapshot.status == TunnelStatus.connected ||
          snapshot.status == TunnelStatus.connecting ||
          snapshot.status == TunnelStatus.error,
    });
  }

  void dispose() {
    if (!_initialized) return;
    _settings.removeListener(_onSettingsChanged);
    _tunnel.removeListener(_onTunnelChanged);
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }
}
