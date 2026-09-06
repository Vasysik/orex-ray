import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/apps/app_routing_controller.dart';
import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../core/xray/xray_config_builder.dart';

class AndroidXrayEngine
    implements
        TunnelEngine,
        TunnelInitialStateSync,
        TunnelRuntimeMetadataSink,
        TunnelRuntimeEffectiveLatencySink,
        TunnelRuntimeSettingsSink,
        TunnelStatsConsumerSink,
        TunnelDiagnosticsProvider {
  AndroidXrayEngine({
    required ConnectionSettingsController settings,
    required AppRoutingController appRouting,
    XrayConfigBuilder? configBuilder,
    TunnelTarget? Function(String targetId)? targetResolver,
  })  : _settings = settings,
        _appRouting = appRouting,
        _configBuilder = configBuilder ?? const XrayConfigBuilder(),
        _targetResolver = targetResolver {
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
  final TunnelTarget? Function(String targetId)? _targetResolver;
  final _snapshots = StreamController<TunnelSnapshot>.broadcast();
  final _initialStateReady = Completer<void>();
  late final StreamSubscription<dynamic> _eventSubscription;

  TunnelTarget? _activeTarget;
  ConnectionMode _activeMode = ConnectionMode.vpnTun;
  bool _statsUiActive = true;
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
  Future<void> waitForInitialState() => _initialStateReady.future;

  @override
  Future<void> start(TunnelTarget target, ConnectionMode mode) async {
    // A foreground Android VPN service can outlive the Activity/Dart engine.
    // Do not issue another start request until the native state has been
    // hydrated, otherwise we could overwrite metadata for the live route.
    await waitForInitialState();
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
    // Let Flutter present the connecting frame before synchronous config
    // generation. This matters most during in-app profile reconnects.
    await Future<void>.delayed(Duration.zero);

    try {
      final config = mode == ConnectionMode.vpnTun
          ? _configBuilder.buildAndroidTun(
              target,
              mtu: _settings.mtu,
              socksPort: _settings.socksPort,
              httpPort: _settings.httpPort,
              allowLan: _settings.allowLan,
              localProxyInVpn: _settings.localProxyInVpn,
              bypassPrivateNetworks: _settings.bypassPrivateNetworks,
              sniffingEnabled: _settings.sniffingEnabled,
              geoRoutingEnabled: _settings.geoRoutingEnabled,
              geoDirectRules: _settings.geoDirectRules,
              geoProxyRules: _settings.geoProxyRules,
              geoBlockRules: _settings.geoBlockRules,
              logLevel: _settings.logLevel,
              balancerProbeUrl: _settings.latencyProbeUrl,
            )
          : _configBuilder.buildLocalProxy(
              target,
              socksPort: _settings.socksPort,
              httpPort: _settings.httpPort,
              allowLan: _settings.allowLan,
              bypassPrivateNetworks: _settings.bypassPrivateNetworks,
              sniffingEnabled: _settings.sniffingEnabled,
              geoRoutingEnabled: _settings.geoRoutingEnabled,
              geoDirectRules: _settings.geoDirectRules,
              geoProxyRules: _settings.geoProxyRules,
              geoBlockRules: _settings.geoBlockRules,
              logLevel: _settings.logLevel,
              balancerProbeUrl: _settings.latencyProbeUrl,
              enableInboundStats: false,
            );
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'config': config,
        'mode': mode.storageValue,
        'targetId': target.id,
        'targetName': target.name,
        // The saved profile value is only a direct TCP handshake.  The
        // foreground notification must wait for TunnelController's
        // end-to-end active-route measurement instead of showing it as VPN
        // latency while the route check is still pending.
        'latencyMs': null,
        'pingStatus': PingStatus.unknown.storageValue,
        'latencyProbeUrl': _settings.latencyProbeUrl,
        'statsOutboundTags': target.isBalancer
            ? [
                for (var index = 0; index < target.profiles.length; index++)
                  'proxy-$index',
                if (target.fallbackProfile != null) 'fallback-proxy',
              ]
            : const ['proxy'],
        'mtu': _settings.mtu,
        'dnsServers': _settings.dnsServers,
        'socksPort': _settings.socksPort,
        'httpPort': _settings.httpPort,
        'localProxyInVpn': _settings.localProxyInVpn,
        'statsIntervalSeconds': _settings.statsIntervalSeconds,
        'notificationStatsIntervalSeconds':
            _settings.notificationStatsIntervalSeconds,
        'pingIntervalSeconds': _settings.pingIntervalSeconds,
        'showNotificationSpeed': _settings.showNotificationSpeed,
        'showNotificationPing': _settings.showNotificationPing,
        'statsUiActive': _statsUiActive,
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
  Future<void> updateTargetMetadata(TunnelTarget target) => _updateTargetMetadata(
        target,
        latencyMs: target.latencyMs,
        pingStatus: target.pingStatus,
      );

  @override
  Future<void> updateEffectiveLatency(
    TunnelTarget target, {
    required int? latencyMs,
    required PingStatus pingStatus,
  }) =>
      _updateTargetMetadata(
        target,
        latencyMs: latencyMs,
        pingStatus: pingStatus,
      );

  Future<void> _updateTargetMetadata(
    TunnelTarget target, {
    required int? latencyMs,
    required PingStatus pingStatus,
  }) async {
    _activeTarget = target;
    try {
      await _channel
          .invokeMethod<void>('updateTargetMetadata', <String, Object?>{
        'targetId': target.id,
        'targetName': target.name,
        'latencyMs': latencyMs,
        'pingStatus': pingStatus.storageValue,
        'latencyProbeUrl': _settings.latencyProbeUrl,
      });
    } catch (_) {
      // Runtime metadata is best-effort and must never interrupt the tunnel.
    }
  }

  @override
  Future<void> updateRuntimeSettings({
    required int statsIntervalSeconds,
    required int notificationStatsIntervalSeconds,
    required int pingIntervalSeconds,
    required bool showNotificationSpeed,
    required bool showNotificationPing,
  }) async {
    if (!_current.isConnected) return;
    try {
      await _channel
          .invokeMethod<void>('updateRuntimeSettings', <String, Object?>{
        'statsIntervalSeconds': statsIntervalSeconds,
        'notificationStatsIntervalSeconds': notificationStatsIntervalSeconds,
        'pingIntervalSeconds': pingIntervalSeconds,
        'showNotificationSpeed': showNotificationSpeed,
        'showNotificationPing': showNotificationPing,
      });
    } catch (_) {
      // Settings synchronization is best-effort and must not interrupt a
      // running VPN when the Android service is being restarted.
    }
  }

  @override
  Future<void> setStatsUiActive(bool active) async {
    _statsUiActive = active;
    if (!_current.isConnected) return;
    await _pushStatsUiActive();
  }

  Future<void> _pushStatsUiActive() async {
    try {
      await _channel.invokeMethod<void>('setStatsUiActive', _statsUiActive);
    } catch (_) {
      // The app may be closing while Android has already released the native
      // activity. The service will fall back to the notification consumer.
    }
  }

  @override
  Future<TunnelDiagnostics> collectDiagnostics() async {
    Map<String, dynamic>? native;
    try {
      native = await _channel.invokeMapMethod<String, dynamic>('diagnostics');
    } catch (_) {
      native = null;
    }
    final logs = (native?['logs'] as List?)
            ?.whereType<String>()
            .map(DiagnosticSanitizer.sanitize)
            .toList(growable: false) ??
        const <String>[];
    return TunnelDiagnostics(
      platform: 'Android',
      xrayVersion: '26.6.27 (embedded libv2ray)',
      mode: _current.mode,
      targetName: _current.profile?.name ?? _activeTarget?.name ?? '—',
      xrayState:
          native?['coreRunning'] == true ? 'running' : _current.status.name,
      pid: (native?['pid'] as num?)?.toInt(),
      ports: {'SOCKS': _settings.socksPort, 'HTTP': _settings.httpPort},
      systemProxyStatus: 'not applicable',
      lastError: DiagnosticSanitizer.sanitize(
        (native?['lastError'] as String?) ?? _current.errorMessage ?? '',
      ).trim().isEmpty
          ? null
          : DiagnosticSanitizer.sanitize(
              (native?['lastError'] as String?) ?? _current.errorMessage ?? '',
            ),
      lastExitCode: (native?['lastExitCode'] as num?)?.toInt(),
      outboundInterface: 'Android VpnService',
      routeSummary: 'Android VpnService managed route',
      restartSummary:
          '${(native?['automaticRestarts'] as num?)?.toInt() ?? 0} automatic · service restart ${_settings.restartServiceOnKill ? 'enabled' : 'disabled'}',
      logs: logs,
    );
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
    } finally {
      if (!_initialStateReady.isCompleted) _initialStateReady.complete();
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is Map) _applyEvent(Map<String, dynamic>.from(event));
  }

  void _applyEvent(Map<String, dynamic> event) {
    final wasConnected = _current.isConnected;
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

    final targetId = (event['targetId'] as String?)?.trim();
    if (targetId != null && targetId.isNotEmpty) {
      final resolved = _targetResolver?.call(targetId);
      // Never replace an unknown restored target with the currently selected
      // profile. That would make its saved direct ping look like a VPN route.
      if (resolved?.id == targetId) {
        _activeTarget = resolved;
      } else if (_activeTarget?.id != targetId) {
        _activeTarget = null;
      }
    }

    final downloadBytes = (event['downloadBytes'] as num?)?.toInt() ?? 0;
    final uploadBytes = (event['uploadBytes'] as num?)?.toInt() ?? 0;
    final downBps = (event['downloadBytesPerSecond'] as num?)?.toInt() ?? 0;
    final upBps = (event['uploadBytesPerSecond'] as num?)?.toInt() ?? 0;
    final durationSeconds = (event['durationSeconds'] as num?)?.toInt() ?? 0;
    final effectiveLatencyMs = (event['latencyMs'] as num?)?.toInt();
    final effectivePingStatus =
        PingStatus.fromStorageValue(event['pingStatus'] as String?) ??
            (effectiveLatencyMs == null
                ? PingStatus.unknown
                : PingStatus.success);

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
        effectiveLatencyMs: effectiveLatencyMs,
        effectivePingStatus: effectivePingStatus,
        message: event['message'] as String?,
        errorMessage: event['errorMessage'] as String?,
      ),
    );
    if (status == TunnelStatus.connected && !wasConnected) {
      unawaited(_pushStatsUiActive());
    }
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
