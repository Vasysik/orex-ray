import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../features/home/tunnel_controller.dart';

class WindowsLifecycleController {
  WindowsLifecycleController({
    required TunnelController tunnel,
    required ConnectionSettingsController settings,
  })  : _tunnel = tunnel,
        _settings = settings;

  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');
  static const _networkDebounce = Duration(seconds: 3);
  static const _resumeDebounce = Duration(milliseconds: 1200);
  static const _networkCooldown = Duration(seconds: 4);

  final TunnelController _tunnel;
  final ConnectionSettingsController _settings;
  bool _initialized = false;
  bool _exitInProgress = false;
  String? _lastTrayState;
  Timer? _recoveryDebounce;
  bool _recoveryInProgress = false;
  TunnelRecoveryReason? _pendingRecoveryReason;
  DateTime? _networkCooldownUntil;
  bool? _lastStartupEnabled;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    _settings.addListener(_onSettingsChanged);
    _tunnel.addListener(_onTunnelChanged);
    await _syncCloseBehavior();
    await _syncStartupRegistration();
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
      case 'powerResume':
        _scheduleRecovery(TunnelRecoveryReason.systemResume);
        return;
      case 'networkChanged':
        _scheduleRecovery(TunnelRecoveryReason.networkChanged);
        return;
      default:
        throw MissingPluginException(
          'Unknown Windows lifecycle method: ${call.method}',
        );
    }
  }

  void _onSettingsChanged() {
    unawaited(_syncCloseBehavior());
    unawaited(_syncStartupRegistration());
  }

  void _onTunnelChanged() {
    unawaited(_syncTrayStatus());
  }

  void _scheduleRecovery(TunnelRecoveryReason reason) {
    if (_recoveryInProgress) {
      // Re-evaluate the network after the current recovery. A second physical
      // switch can happen while Xray is stopping/starting; dropping it would
      // leave the new TUN bound to the adapter that just disappeared. Resume
      // is stronger than a generic interface notification.
      if (_pendingRecoveryReason != TunnelRecoveryReason.systemResume ||
          reason == TunnelRecoveryReason.systemResume) {
        _pendingRecoveryReason = reason;
      }
      return;
    }

    final now = DateTime.now();
    final cooldownUntil = _networkCooldownUntil;
    if (reason == TunnelRecoveryReason.networkChanged &&
        cooldownUntil?.isAfter(now) == true) {
      // Do not drop a real interface transition just because it happened soon
      // after a previous recovery. Re-check once the short anti-loop cooldown
      // expires; the engine will ignore it if the physical adapter is unchanged.
      _recoveryDebounce?.cancel();
      _recoveryDebounce = Timer(
        cooldownUntil!.difference(now),
        () => unawaited(_runRecovery(reason)),
      );
      return;
    }

    _recoveryDebounce?.cancel();
    final delay = reason == TunnelRecoveryReason.systemResume
        ? _resumeDebounce
        : _networkDebounce;
    _recoveryDebounce = Timer(delay, () => unawaited(_runRecovery(reason)));
  }

  Future<void> _runRecovery(TunnelRecoveryReason reason) async {
    if (_recoveryInProgress) return;
    _recoveryInProgress = true;
    try {
      await _tunnel.recover(reason);
    } finally {
      _recoveryInProgress = false;
      _networkCooldownUntil = DateTime.now().add(_networkCooldown);
      final pending = _pendingRecoveryReason;
      _pendingRecoveryReason = null;
      if (pending != null && _initialized) {
        _recoveryDebounce?.cancel();
        _recoveryDebounce = Timer(_networkCooldown, () {
          if (_initialized) unawaited(_runRecovery(pending));
        });
      }
    }
  }

  Future<void> _syncStartupRegistration() async {
    if (_lastStartupEnabled == _settings.autoStart) return;
    try {
      await _channel.invokeMethod<void>(
        'setStartupEnabled',
        _settings.autoStart,
      );
      _lastStartupEnabled = _settings.autoStart;
    } catch (_) {
      // Startup registration is optional. Keep the previous cached value so a
      // later settings change or launch can retry without breaking lifecycle.
    }
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
    final timedOut = snapshot.isConnected &&
        _tunnel.effectivePingStatusFor(snapshot.profile) == PingStatus.timeout;
    final trayStatus = timedOut ? 'timeout' : snapshot.status.name;
    final stateKey = '$trayStatus|${targetName ?? ''}';
    if (_lastTrayState == stateKey) return;
    _lastTrayState = stateKey;

    await _channel.invokeMethod<void>('updateTray', {
      'status': trayStatus,
      'targetName': targetName,
      'canDisconnect': snapshot.status == TunnelStatus.connected ||
          snapshot.status == TunnelStatus.connecting ||
          snapshot.status == TunnelStatus.error,
    });
  }

  void dispose() {
    if (!_initialized) return;
    _recoveryDebounce?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _tunnel.removeListener(_onTunnelChanged);
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }
}
