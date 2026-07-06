import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/apps/app_routing_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../core/xray/xray_config_builder.dart';

class AndroidXrayEngine implements TunnelEngine {
  AndroidXrayEngine({
    required ConnectionSettingsController settings,
    required AppRoutingController appRouting,
    XrayConfigBuilder? configBuilder,
  })  : _settings = settings,
        _appRouting = appRouting,
        _configBuilder = configBuilder ?? const XrayConfigBuilder() {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: _onNativeStreamError,
    );
    unawaited(_syncNativeStatus());
  }

  static const _channel = MethodChannel('ru.orex.ray/tunnel');
  static const _events = EventChannel('ru.orex.ray/tunnel_events');

  final ConnectionSettingsController _settings;
  final AppRoutingController _appRouting;
  final XrayConfigBuilder _configBuilder;
  final _snapshots = StreamController<TunnelSnapshot>.broadcast();
  late final StreamSubscription<dynamic> _eventSubscription;

  TunnelTarget? _activeTarget;
  ConnectionMode _activeMode = ConnectionMode.vpnTun;
  TunnelSnapshot _current = const TunnelSnapshot(
    status: TunnelStatus.disconnected,
    stats: TrafficStats(),
  );

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _snapshots.stream;

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
      };

  @override
  Future<void> start(TunnelTarget target, ConnectionMode mode) async {
    if (_current.isBusy || _current.isConnected) return;
    if (!supportedModes.contains(mode)) {
      _emitError('Этот режим не поддерживается на Android.', mode: mode);
      return;
    }

    _activeTarget = target;
    _activeMode = mode;
    _emit(
      TunnelSnapshot(
        status: TunnelStatus.connecting,
        mode: mode,
        profile: target,
        stats: const TrafficStats(),
        message: mode == ConnectionMode.vpnTun
            ? 'Готовим Android VPN…'
            : 'Запускаем локальный прокси…',
      ),
    );

    try {
      final config = mode == ConnectionMode.vpnTun
          ? _configBuilder.buildAndroidTun(
              target,
              mtu: _settings.mtu,
              bypassPrivateNetworks: _settings.bypassPrivateNetworks,
              sniffingEnabled: _settings.sniffingEnabled,
              logLevel: _settings.logLevel,
            )
          : _configBuilder.buildLocalProxy(
              target,
              socksPort: _settings.socksPort,
              httpPort: _settings.httpPort,
              allowLan: _settings.allowLan,
              bypassPrivateNetworks: _settings.bypassPrivateNetworks,
              sniffingEnabled: _settings.sniffingEnabled,
              logLevel: _settings.logLevel,
            );
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'config': config,
        'mode': mode.storageValue,
        'targetName': target.name,
        'statsOutboundTags': target.isBalancer
            ? [
                for (var index = 0; index < target.profiles.length; index++)
                  'proxy-$index',
              ]
            : const ['proxy'],
        'mtu': _settings.mtu,
        'dnsServers': _settings.dnsServers,
        'socksPort': _settings.socksPort,
        'httpPort': _settings.httpPort,
        'statsIntervalSeconds': _settings.statsIntervalSeconds,
        'showNotificationSpeed': _settings.showNotificationSpeed,
        'restartServiceOnKill': _settings.restartServiceOnKill,
        'appRoutingMode': _appRouting.mode.storageValue,
        'appPackages': _appRouting.selectedPackages.toList(growable: false),
      });
    } on PlatformException catch (error) {
      _emitError(error.message ?? error.code, mode: mode);
    } catch (error) {
      _emitError(error.toString(), mode: mode);
    }
  }

  @override
  Future<void> stop() async {
    if (_current.status == TunnelStatus.disconnected ||
        _current.status == TunnelStatus.disconnecting) {
      return;
    }

    _emit(
      _current.copyWith(
        status: TunnelStatus.disconnecting,
        message: 'Останавливаем OrexRay…',
        clearError: true,
      ),
    );

    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      _emitError(error.message ?? error.code, mode: _current.mode);
    } catch (error) {
      _emitError(error.toString(), mode: _current.mode);
    }
  }

  Future<void> _syncNativeStatus() async {
    try {
      final event = await _channel.invokeMapMethod<String, dynamic>('status');
      if (event != null) _applyEvent(event);
    } catch (_) {
      // EventChannel delivers the first live state after attachment.
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is Map) _applyEvent(Map<String, dynamic>.from(event));
  }

  void _applyEvent(Map<String, dynamic> event) {
    final status = switch (event['status']) {
      'connecting' => TunnelStatus.connecting,
      'connected' => TunnelStatus.connected,
      'disconnecting' => TunnelStatus.disconnecting,
      'error' => TunnelStatus.error,
      _ => TunnelStatus.disconnected,
    };

    final mode = ConnectionMode.fromStorageValue(event['mode'] as String?) ??
        _activeMode;
    _activeMode = mode;

    final downloadBytes = (event['downloadBytes'] as num?)?.toInt() ?? 0;
    final uploadBytes = (event['uploadBytes'] as num?)?.toInt() ?? 0;
    final downBps = (event['downloadBytesPerSecond'] as num?)?.toInt() ?? 0;
    final upBps = (event['uploadBytesPerSecond'] as num?)?.toInt() ?? 0;
    final durationSeconds = (event['durationSeconds'] as num?)?.toInt() ?? 0;

    _emit(
      TunnelSnapshot(
        status: status,
        mode: mode,
        profile: _activeTarget,
        stats: TrafficStats(
          downloadBytes: downloadBytes,
          uploadBytes: uploadBytes,
          downloadBytesPerSecond: downBps,
          uploadBytesPerSecond: upBps,
          duration: Duration(seconds: durationSeconds),
        ),
        message: event['message'] as String?,
        errorMessage: event['errorMessage'] as String?,
      ),
    );
  }

  void _onNativeStreamError(Object error) =>
      _emitError(error.toString(), mode: _activeMode);

  void _emitError(String message, {required ConnectionMode mode}) {
    _emit(
      _current.copyWith(
        status: TunnelStatus.error,
        mode: mode,
        profile: _activeTarget,
        errorMessage: message,
        clearMessage: true,
      ),
    );
  }

  void _emit(TunnelSnapshot value) {
    _current = value;
    if (!_snapshots.isClosed) _snapshots.add(value);
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _snapshots.close();
  }
}
