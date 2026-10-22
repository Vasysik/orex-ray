import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_version.dart';
import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../core/xray/xray_config_builder.dart';
import 'windows_elevation_controller.dart';
import 'windows_network_controller.dart';
import 'windows_process_job.dart';
import 'windows_system_proxy_controller.dart';
import 'xray_core_manager.dart';
import 'xray_stats_client.dart';
import 'xray_watchdog.dart';

class WindowsXrayEngine implements
    TunnelEngine,
    TunnelRuntimeSettingsSink,
    TunnelStatsConsumerSink,
    TunnelRecoverySink,
    TunnelDiagnosticsProvider,
    TunnelDiagnosticEventSink,
    TunnelCoreMaintenance {
  WindowsXrayEngine({
    required ConnectionSettingsController settings,
    OrexAppVersion appVersion = OrexAppVersion.fallback,
    XrayCoreManager? coreManager,
    XrayConfigBuilder? configBuilder,
    WindowsSystemProxyController? systemProxyController,
  })  : _settings = settings,
        _activeStatsIntervalSeconds = settings.statsIntervalSeconds,
        _coreManager = coreManager ?? XrayCoreManager(appVersion: appVersion),
        _configBuilder = configBuilder ?? const XrayConfigBuilder(),
        _systemProxy =
            systemProxyController ?? WindowsSystemProxyController(),
        _current = const TunnelSnapshot(
          status: TunnelStatus.disconnected,
          stats: TrafficStats(),
        ) {
    // If the app or PC stopped while OrexRay owned the Windows proxy setting,
    // restore the user's previous state as soon as the app starts again.
    _proxyRecovery = _systemProxy.recoverIfNeeded();
  }

  static const _minimalProxyBypass = '<local>;localhost;127.*';
  static const _privateProxyBypass = <String>[
    '10.*',
    '172.16.*',
    '172.17.*',
    '172.18.*',
    '172.19.*',
    '172.20.*',
    '172.21.*',
    '172.22.*',
    '172.23.*',
    '172.24.*',
    '172.25.*',
    '172.26.*',
    '172.27.*',
    '172.28.*',
    '172.29.*',
    '172.30.*',
    '172.31.*',
    '192.168.*',
  ];

  final ConnectionSettingsController _settings;
  final XrayCoreManager _coreManager;
  final XrayConfigBuilder _configBuilder;
  final WindowsSystemProxyController _systemProxy;
  final _snapshots = StreamController<TunnelSnapshot>.broadcast();
  final List<String> _logs = [];

  late final Future<void> _proxyRecovery;
  Future<void>? _systemProxyEnableFuture;
  Future<void>? _stopFuture;
  Process? _process;
  Timer? _statsTimer;
  Timer? _durationTimer;
  int _activeStatsIntervalSeconds;
  DateTime? _connectedAt;
  XrayStatsClient? _statsClient;
  bool _statsPollInFlight = false;
  bool _statsUiActive = false;
  final Map<String, int> _lastOutboundTrafficTotals = <String, int>{};
  DateTime? _lastStatsAt;
  int? _lastDownloadValue;
  int? _lastUploadValue;
  File? _configFile;
  String? _managedExecutablePath;
  TunnelSnapshot _current;
  ConnectionMode? _activeMode;
  bool _stopping = false;
  bool _disposed = false;
  int _operationId = 0;
  final XrayRestartBudget _restartBudget = XrayRestartBudget();
  TunnelTarget? _desiredTarget;
  ConnectionMode? _desiredMode;
  Future<void>? _recoveryFuture;
  int? _lastExitCode;
  String? _lastError;
  String? _lastOutboundInterface;
  String _lastTunRouteSummary = 'not checked';
  int _automaticRestarts = 0;

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _snapshots.stream;

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.systemProxy,
        ConnectionMode.vpnTun,
        ConnectionMode.localProxy,
      };

  void _emit(TunnelSnapshot snapshot) {
    _current = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }

  void _status(
    TunnelStatus status, {
    ConnectionMode? mode,
    TunnelTarget? profile,
    String? message,
    String? error,
    TrafficStats? stats,
    String? activeBalancerMemberId,
  }) {
    _emit(TunnelSnapshot(
      status: status,
      mode: mode ?? _current.mode,
      profile: profile ?? _current.profile,
      stats: stats ?? _current.stats,
      activeBalancerMemberId: status == TunnelStatus.connected
          ? (activeBalancerMemberId ?? _current.activeBalancerMemberId)
          : null,
      message: message,
      errorMessage: error,
    ));
  }

  bool _isCurrentOperation(int operationId) =>
      !_disposed && operationId == _operationId;

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    _desiredTarget = profile;
    _desiredMode = mode;
    _restartBudget.reset();
    _automaticRestarts = 0;
    await _startInternal(profile, mode);
  }

  Future<void> _startInternal(
    TunnelTarget profile,
    ConnectionMode mode, {
    bool recovery = false,
  }) async {
    if (_disposed ||
        _process != null ||
        (!recovery && (_current.isBusy || _current.isConnected))) {
      return;
    }
    if (!supportedModes.contains(mode)) {
      _status(
        TunnelStatus.error,
        mode: mode,
        profile: profile,
        error: 'Этот режим не поддерживается в Windows.',
      );
      return;
    }

    final operationId = ++_operationId;
    Process? startedProcess;
    _stopping = false;
    if (recovery) {
      _appendAppLog('Automatic recovery start: mode=${mode.storageValue}.');
    } else {
      _logs.clear();
      _appendAppLog(
        'Connection start requested: mode=${mode.storageValue}, '
        'target=${profile.name}.',
      );
    }
    _activeMode = mode;
    _lastOutboundTrafficTotals.clear();
    _lastTunRouteSummary =
        mode == ConnectionMode.vpnTun ? 'checking' : 'not applicable';
    _status(
      TunnelStatus.connecting,
      mode: mode,
      profile: profile,
      message: 'Подготавливаем Xray Core…',
      stats: const TrafficStats(),
    );
    // Paint the connecting state before core verification/config generation.
    await Future<void>.delayed(Duration.zero);

    try {
      await _proxyRecovery;
      if (!_isCurrentOperation(operationId)) return;

      final install = await _coreManager.ensureInstalled(
        onProgress: (progress) {
          if (!_isCurrentOperation(operationId)) return;
          _status(
            TunnelStatus.connecting,
            mode: mode,
            profile: profile,
            message: 'Скачиваем Xray Core · ${(progress * 100).round()}%',
            stats: const TrafficStats(),
          );
        },
      );
      if (!_isCurrentOperation(operationId)) return;
      _managedExecutablePath = install.executable.path;
      _appendAppLog('Xray Core ${XrayCoreManager.version} verified.');

      // Recover from old OrexRay versions that could leave their managed
      // xray.exe alive after the Flutter process exited. The native side only
      // terminates processes whose full executable path exactly matches this
      // OrexRay-managed core path.
      await WindowsProcessJob.terminateStaleProcesses(install.executable.path);
      if (!_isCurrentOperation(operationId)) return;
      _appendAppLog('Stale managed Xray process cleanup completed.');

      final elevated = await WindowsElevationController.isElevated();
      _appendAppLog('Process elevation: ${elevated ? 'elevated' : 'standard'}.');
      final assetDirectory = elevated
          ? install.elevatedAssetDirectory
          : install.assetDirectory;
      final statsApiPort = await _reserveLoopbackPort();
      final outboundInterface = mode == ConnectionMode.vpnTun
          ? await _waitForOutboundInterface()
          : null;
      _lastOutboundInterface = outboundInterface;
      if (mode == ConnectionMode.vpnTun && outboundInterface == null) {
        throw StateError(
          'Не найден активный физический сетевой интерфейс с маршрутом в '
          'интернет. Подключи Wi-Fi, Ethernet или мобильную точку и повтори.',
        );
      }
      if (outboundInterface != null) {
        _appendAppLog('Physical outbound interface: $outboundInterface.');
      }
      final configFile = await _prepareConfigFile(
        install: install,
        elevated: elevated,
      );
      _configFile = configFile;
      final config = switch (mode) {
        ConnectionMode.vpnTun => _configBuilder.buildWindowsTun(
            profile,
            mtu: _settings.mtu,
            dnsServers: _settings.dnsServers,
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
            apiPort: statsApiPort,
            outboundInterface: outboundInterface,
          ),
        ConnectionMode.systemProxy || ConnectionMode.localProxy =>
          _configBuilder.buildLocalProxy(
            profile,
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
            apiPort: statsApiPort,
          ),
      };
      await configFile.writeAsString(config, flush: true);
      if (!_isCurrentOperation(operationId)) return;

      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: 'Проверяем конфигурацию…',
      );
      await _validateConfig(install, configFile, assetDirectory);
      if (!_isCurrentOperation(operationId)) return;
      _appendAppLog('Xray configuration validation passed.');

      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: _startingMessage(mode),
      );
      final processLogs = <String>[];
      startedProcess = await Process.start(
        install.executable.path,
        ['run', '-c', configFile.path],
        workingDirectory: install.directory.path,
        mode: ProcessStartMode.normal,
        environment: {
          'XRAY_LOCATION_ASSET': assetDirectory.path,
        },
      );
      _process = startedProcess;
      _listenLogs(startedProcess, processLogs);
      _appendAppLog('Xray process started: PID ${startedProcess.pid}.');

      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess, install.executable.path);
        if (_process == startedProcess) _process = null;
        return;
      }

      // Make Xray an OS-owned child of OrexRay before treating it as started.
      // Closing the OrexRay process then kills Xray even after a crash or a
      // forced process termination that bypasses Dart cleanup.
      await WindowsProcessJob.attach(startedProcess.pid);
      _appendAppLog('Xray PID ${startedProcess.pid} attached to process job.');
      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess, install.executable.path);
        if (_process == startedProcess) _process = null;
        return;
      }

      final earlyExit = await Future.any<int?>([
        startedProcess.exitCode.then<int?>((value) => value),
        Future<int?>.delayed(const Duration(milliseconds: 900), () => null),
      ]);
      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess, install.executable.path);
        if (_process == startedProcess) _process = null;
        return;
      }
      if (earlyExit != null) {
        if (_process == startedProcess) _process = null;
        throw StateError(
          _bestError(
            'Xray завершился с кодом $earlyExit',
            logs: processLogs,
          ),
        );
      }

      if (mode == ConnectionMode.vpnTun) {
        try {
          final routeStatus = await WindowsNetworkController.tunRouteStatus();
          _lastTunRouteSummary = 'advisory · ${routeStatus.summary}';
          _appendAppLog(
            'TUN route observation (advisory): ${routeStatus.summary}.',
          );
          if (!routeStatus.fullyCaptured) {
            _appendAppLog(
              'Windows best-route API does not identify OrexRay as the best '
              'public route. Continuing because this API is not a reliable '
              'health check for Xray TUN traffic.',
            );
          }
        } catch (error) {
          _lastTunRouteSummary = 'advisory check unavailable';
          _appendAppLog('TUN route observation failed: $error');
        }
      } else {
        _lastTunRouteSummary = 'not applicable';
      }

      if (mode == ConnectionMode.systemProxy) {
        _status(
          TunnelStatus.connecting,
          mode: mode,
          profile: profile,
          message: 'Включаем системный прокси Windows…',
        );
        final enableFuture = _systemProxy
            .enable(
              server: '127.0.0.1:${_settings.httpPort}',
              bypass: _proxyBypass(
                includePrivateNetworks: _settings.bypassPrivateNetworks,
              ),
            )
            .then<void>((_) {});
        _systemProxyEnableFuture = enableFuture;
        try {
          await enableFuture;
        } finally {
          if (_systemProxyEnableFuture == enableFuture) {
            _systemProxyEnableFuture = null;
          }
        }
        _appendAppLog(
          'Windows system proxy enabled on 127.0.0.1:${_settings.httpPort}.',
        );
        if (!_isCurrentOperation(operationId)) {
          await _restoreSystemProxy();
          await _terminateProcessTree(startedProcess, install.executable.path);
          if (_process == startedProcess) _process = null;
          return;
        }
      }

      _connectedAt = DateTime.now();
      _lastStatsAt = null;
      _lastDownloadValue = null;
      _lastUploadValue = null;
      _statsClient = XrayStatsClient(port: statsApiPort);
      _status(
        TunnelStatus.connected,
        mode: mode,
        profile: profile,
        message: _connectedMessage(mode),
        stats: const TrafficStats(),
      );
      _appendAppLog(
        'Connection established: mode=${mode.storageValue}, '
        'PID=${startedProcess.pid}.',
      );
      _startTelemetry();

      unawaited(
        startedProcess.exitCode.then(
          (code) => _handleUnexpectedExit(
            process: startedProcess!,
            code: code,
            profile: profile,
            mode: mode,
            processLogs: processLogs,
          ),
        ),
      );
    } catch (error) {
      final canceled = !_isCurrentOperation(operationId);
      final process = startedProcess;
      if (process != null) {
        await _terminateProcessTree(
          process,
          _managedExecutablePath ?? '',
        );
        if (_process == process) _process = null;
      }
      _statsTimer?.cancel();
      _durationTimer?.cancel();
      await _closeStatsClient();
      if (mode == ConnectionMode.systemProxy) {
        await _restoreSystemProxy();
      }
      _resetRuntimeState();

      if (!canceled && !_disposed) {
        _lastError = _friendlyError(error, mode);
        _appendAppLog('Connection start failed: $_lastError');
        _status(
          TunnelStatus.error,
          mode: mode,
          profile: profile,
          error: _lastError,
          stats: const TrafficStats(),
        );
      }
      if (_activeMode == mode) _activeMode = null;
    }
  }

  Future<void> _handleUnexpectedExit({
    required Process process,
    required int code,
    required TunnelTarget profile,
    required ConnectionMode mode,
    required List<String> processLogs,
  }) async {
    if (_process != process || _stopping || _disposed || _snapshots.isClosed) {
      return;
    }
    _process = null;
    _lastExitCode = code;
    _appendAppLog('Xray PID ${process.pid} exited unexpectedly with code $code.');
    _statsTimer?.cancel();
    _durationTimer?.cancel();
    await _closeStatsClient();
    if (_activeMode == ConnectionMode.systemProxy) await _restoreSystemProxy();
    _resetRuntimeState();

    final decision = XrayExitClassifier.classify(
      exitCode: code,
      logs: processLogs,
    );
    final detail = _bestError(decision.message, logs: processLogs);
    _lastError = detail;
    _appendAppLog(
      'Watchdog classification: ${decision.kind.name}; '
      'restart=${decision.canRestart}. Detail: $detail',
    );
    final shouldRecover = _desiredTarget?.id == profile.id &&
        _desiredMode == mode &&
        decision.canRestart;

    if (shouldRecover && _restartBudget.tryTake()) {
      _automaticRestarts++;
      final delay = switch (_restartBudget.recentRestartCount) {
        1 => const Duration(seconds: 1),
        2 => const Duration(seconds: 3),
        _ => const Duration(seconds: 8),
      };
      _appendAppLog(
        'Watchdog: ${decision.kind.name}; restart '
        '${_restartBudget.recentRestartCount}/${_restartBudget.maxRestarts} '
        'in ${delay.inSeconds}s.',
      );
      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: 'Xray перезапускается после сбоя…',
        stats: const TrafficStats(),
      );
      await Future<void>.delayed(delay);
      if (_disposed || _stopping || _desiredTarget?.id != profile.id) return;
      await _startInternal(profile, mode, recovery: true);
      return;
    }

    final budgetExhausted = shouldRecover &&
        _restartBudget.recentRestartCount >= _restartBudget.maxRestarts;
    _status(
      code == 0 && !shouldRecover
          ? TunnelStatus.disconnected
          : TunnelStatus.error,
      mode: mode,
      profile: profile,
      error: budgetExhausted
          ? '$detail\nWatchdog остановлен: не больше '
              '${_restartBudget.maxRestarts} перезапусков за минуту.'
          : detail,
      stats: const TrafficStats(),
    );
    _activeMode = null;
  }

  @override
  Future<void> recover(TunnelRecoveryReason reason) {
    final pending = _recoveryFuture;
    if (pending != null) return pending;
    final target = _desiredTarget;
    final mode = _desiredMode;
    if (target == null || mode == null || _disposed || _stopping) {
      return Future<void>.value();
    }

    late final Future<void> future;
    future = _recoverInternal(target, mode, reason).whenComplete(() {
      if (_recoveryFuture == future) _recoveryFuture = null;
    });
    _recoveryFuture = future;
    return future;
  }

  Future<void> _recoverInternal(
    TunnelTarget target,
    ConnectionMode mode,
    TunnelRecoveryReason reason,
  ) async {
    _appendAppLog('Recovery event received: ${reason.name}.');

    if (reason == TunnelRecoveryReason.networkChanged) {
      if (mode != ConnectionMode.vpnTun) {
        _appendAppLog(
          'Network event ignored: ${mode.storageValue} keeps local listeners '
          'alive and Xray reconnects outbound sockets itself.',
        );
        return;
      }

      final candidate = await _waitForOutboundInterface(
        attempts: 10,
        previousInterface: _lastOutboundInterface,
        waitForChange: true,
      );
      if (candidate == null) {
        _appendAppLog(
          'Network event deferred: no usable physical interface is ready yet.',
        );
        return;
      }
      if (candidate == _lastOutboundInterface && _process != null) {
        _appendAppLog(
          'Network event ignored: physical interface is still $candidate.',
        );
        return;
      }
      _appendAppLog(
        'Physical interface changed: '
        '${_lastOutboundInterface ?? 'unknown'} -> $candidate. Rebuilding TUN.',
      );
    } else {
      _appendAppLog('System resumed; rebuilding the active connection once.');
    }

    ++_operationId;
    await _stopInternal();
    if (_disposed || _desiredTarget?.id != target.id || _desiredMode != mode) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await _startInternal(target, mode, recovery: true);
  }

  @override
  Future<void> reinstallCore({
    void Function(double progress)? onProgress,
  }) async {
    if (_process != null || _current.isBusy || _current.isConnected) {
      throw StateError('Сначала отключи активное соединение.');
    }
    final protectedInstall = await WindowsElevationController.isProtectedInstall();
    if (protectedInstall && !await WindowsElevationController.isElevated()) {
      throw StateError(
        'Для записи в Program Files нужны права администратора.',
      );
    }
    _appendAppLog('Xray Core reinstall requested.');
    await _coreManager.reinstall(onProgress: onProgress);
    _appendAppLog('Xray Core ${XrayCoreManager.version} reinstalled and verified.');
    _lastError = null;
  }

  @override
  Future<TunnelDiagnostics> collectDiagnostics() async {
    if ((_activeMode ?? _current.mode) == ConnectionMode.vpnTun &&
        _process != null) {
      try {
        final routeStatus = await WindowsNetworkController.tunRouteStatus();
        _lastTunRouteSummary = 'advisory · ${routeStatus.summary}';
      } catch (error) {
        _appendAppLog('Live TUN route diagnostics failed: $error');
      }
    }
    final proxyState = await _systemProxy.read();
    final proxyStatus = proxyState.enabled
        ? 'enabled · ${proxyState.server.isEmpty ? 'unknown' : proxyState.server}'
        : 'disabled';
    return TunnelDiagnostics(
      platform: 'Windows',
      xrayVersion: XrayCoreManager.version,
      mode: _activeMode ?? _current.mode,
      targetName: _current.profile?.name ?? _desiredTarget?.name ?? '—',
      xrayState: _current.status.name,
      pid: _process?.pid,
      ports: {
        'SOCKS': _settings.socksPort,
        'HTTP': _settings.httpPort,
      },
      systemProxyStatus: proxyStatus,
      lastError: _lastError == null
          ? null
          : DiagnosticSanitizer.sanitize(_lastError!),
      lastExitCode: _lastExitCode,
      outboundInterface: _lastOutboundInterface,
      routeSummary: _lastTunRouteSummary,
      restartSummary:
          '$_automaticRestarts automatic · ${_restartBudget.recentRestartCount}/${_restartBudget.maxRestarts} in current window',
      logs: [
        for (final line in _logs.skip(_logs.length > 100 ? _logs.length - 100 : 0))
          DiagnosticSanitizer.sanitize(line),
      ],
    );
  }

  Future<void> _validateConfig(
    XrayCoreInstall install,
    File configFile,
    Directory assetDirectory,
  ) async {
    final process = await Process.start(
      install.executable.path,
      ['run', '-test', '-c', configFile.path],
      workingDirectory: install.directory.path,
      mode: ProcessStartMode.normal,
      environment: {
        'XRAY_LOCATION_ASSET': assetDirectory.path,
      },
    );
    _process = process;

    try {
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      Object? attachError;
      try {
        await WindowsProcessJob.attach(process.pid);
      } catch (error) {
        attachError = error;
      }

      int exitCode;
      if (attachError == null) {
        exitCode = await process.exitCode;
      } else {
        // `run -test` can finish before the platform channel manages to open
        // its PID. In that harmless race, trust the completed validation. A
        // still-running process must be job-owned, so a real attach failure is
        // fatal and the process is terminated below.
        final earlyExit = await Future.any<int?>([
          process.exitCode.then<int?>((value) => value),
          Future<int?>.delayed(
            const Duration(milliseconds: 100),
            () => null,
          ),
        ]);
        if (earlyExit == null) throw attachError;
        exitCode = earlyExit;
      }

      final output = '${await stderr}\n${await stdout}'.trim();
      if (exitCode != 0) {
        throw FormatException(
          output.isEmpty ? 'Xray отклонил конфигурацию.' : output,
        );
      }
    } catch (_) {
      await _terminateProcessTree(process, install.executable.path);
      rethrow;
    } finally {
      if (_process == process) _process = null;
    }
  }

  void _listenLogs(Process process, List<String> processLogs) {
    void capture(String line) {
      final clean = line.trim();
      if (clean.isEmpty) return;
      processLogs.add(clean);
      if (processLogs.length > 100) processLogs.removeAt(0);
      _appendXrayLog(clean);
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
  }

  @override
  void addDiagnosticEvent(String message) => _appendAppLog(message);

  void _appendXrayLog(String message) {
    _appendDiagnosticLog('[Xray] ${message.trim()}');
  }

  void _appendAppLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _appendDiagnosticLog('$timestamp [OrexRay] $message');
  }

  void _appendDiagnosticLog(String line) {
    final clean = line.trim();
    if (clean.isEmpty) return;
    _logs.add(clean);
    while (_logs.length > 100) {
      // Debug-level Xray traffic can emit hundreds of lines per second. Keep
      // OrexRay lifecycle/recovery decisions visible by evicting the oldest
      // Xray line first instead of letting traffic noise drown app logs.
      final xrayIndex = _logs.indexWhere((entry) => entry.startsWith('[Xray] '));
      _logs.removeAt(xrayIndex >= 0 ? xrayIndex : 0);
    }
  }

  String _bestError(String fallback, {Iterable<String>? logs}) {
    final source = logs?.toList(growable: false) ?? _logs;
    for (final line in source.reversed) {
      final normalized = line.toLowerCase();
      if (normalized.contains('failed') ||
          normalized.contains('error') ||
          normalized.contains('permission') ||
          normalized.contains('access')) {
        return line;
      }
    }
    return fallback;
  }

  String _friendlyError(Object error, ConnectionMode mode) {
    final text = error.toString().replaceFirst('Bad state: ', '').trim();
    final normalized = text.toLowerCase();
    if (mode == ConnectionMode.vpnTun &&
        (normalized.contains('access is denied') ||
            normalized.contains('access denied') ||
            normalized.contains('permission'))) {
      return 'Для режима VPN Windows нужны права администратора. '
          'Системный и локальный прокси работают без них.';
    }
    if (text.contains('SocketException') || text.contains('HttpException')) {
      return 'Не удалось скачать Xray Core. Проверь интернет и попробуй снова.\n$text';
    }
    return text;
  }

  void _startTelemetry() {
    _statsTimer?.cancel();
    _durationTimer?.cancel();

    _activeStatsIntervalSeconds = _settings.statsIntervalSeconds;
    _startStatsTimer(pollImmediately: false);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connectedAt = _connectedAt;
      if (_process == null || connectedAt == null) return;
      _updateStatsDurationOnly(DateTime.now().difference(connectedAt));
    });
    unawaited(_pollStats());
  }

  void _startStatsTimer({bool pollImmediately = true}) {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      Duration(seconds: _activeStatsIntervalSeconds),
      (_) => unawaited(_pollStats()),
    );
    if (pollImmediately) unawaited(_pollStats());
  }

  @override
  Future<void> setStatsUiActive(bool active) async {
    if (_statsUiActive == active) return;
    _statsUiActive = active;
    // Start a fresh baseline when the UI becomes visible. This avoids treating
    // traffic accumulated while hidden as the "current" balancer member.
    _lastOutboundTrafficTotals.clear();
  }

  @override
  Future<void> updateRuntimeSettings({
    required int statsIntervalSeconds,
    required int notificationStatsIntervalSeconds,
    required int pingIntervalSeconds,
    required bool showNotificationSpeed,
    required bool showNotificationPing,
  }) async {
    if (_activeStatsIntervalSeconds == statsIntervalSeconds) return;
    _activeStatsIntervalSeconds = statsIntervalSeconds;
    if (_disposed || _process == null || !_current.isConnected) return;

    // Windows UI statistics are produced by this timer. Ping cadence is
    // managed by TunnelController; notification-only settings are Android
    // concerns, so changing them does not restart Xray or the duration timer.
    _startStatsTimer();
  }

  Future<void> _pollStats() async {
    final client = _statsClient;
    final connectedAt = _connectedAt;
    if (_process == null ||
        client == null ||
        connectedAt == null ||
        _statsPollInFlight) {
      return;
    }

    _statsPollInFlight = true;
    try {
      final totals = await client.queryInboundTotals();
      if (_process == null || _connectedAt != connectedAt) return;

      String? activeBalancerMemberId = _current.activeBalancerMemberId;
      final target = _current.profile;
      if (_statsUiActive && target?.isBalancer == true) {
        try {
          final outboundTotals = await client.queryOutboundTotals();
          if (_process == null || _connectedAt != connectedAt) return;
          var bestDelta = 0;
          String? bestTag;
          if (_lastOutboundTrafficTotals.isNotEmpty) {
            for (final entry in outboundTotals.entries) {
              final previous = _lastOutboundTrafficTotals[entry.key];
              if (previous == null) continue;
              final delta = entry.value - previous;
              if (delta > bestDelta) {
                bestDelta = delta;
                bestTag = entry.key;
              }
            }
          }
          _lastOutboundTrafficTotals
            ..clear()
            ..addAll(outboundTotals);
          if (bestTag != null) {
            activeBalancerMemberId = _profileIdForOutboundTag(target!, bestTag);
          }
        } catch (error) {
          _appendAppLog('Balancer outbound stats query failed: $error');
        }
      } else if (target?.isBalancer != true) {
        _lastOutboundTrafficTotals.clear();
        activeBalancerMemberId = null;
      }

      final now = DateTime.now();
      final seconds = _lastStatsAt == null
          ? 0.0
          : now.difference(_lastStatsAt!).inMilliseconds / 1000.0;
      final download = totals.downloadBytes;
      final upload = totals.uploadBytes;
      final downBps = seconds > 0 && _lastDownloadValue != null
          ? ((download - _lastDownloadValue!) / seconds)
              .round()
              .clamp(0, 1 << 60)
              .toInt()
          : 0;
      final upBps = seconds > 0 && _lastUploadValue != null
          ? ((upload - _lastUploadValue!) / seconds)
              .round()
              .clamp(0, 1 << 60)
              .toInt()
          : 0;

      _lastStatsAt = now;
      _lastDownloadValue = download;
      _lastUploadValue = upload;
      _status(
        TunnelStatus.connected,
        mode: _activeMode,
        message: _connectedMessage(_activeMode ?? ConnectionMode.localProxy),
        stats: TrafficStats(
          downloadBytes: download,
          uploadBytes: upload,
          downloadBytesPerSecond: downBps,
          uploadBytesPerSecond: upBps,
          duration: now.difference(connectedAt),
        ),
        activeBalancerMemberId: activeBalancerMemberId,
      );
    } catch (error) {
      _appendAppLog('Stats API query failed: $error');
    } finally {
      _statsPollInFlight = false;
    }
  }

  String? _profileIdForOutboundTag(TunnelTarget target, String tag) {
    if (!target.isBalancer) return null;
    if (tag == 'fallback-proxy') return target.fallbackProfile?.id;
    final match = RegExp(r'^proxy-(\d+)$').firstMatch(tag);
    final index = match == null ? null : int.tryParse(match.group(1)!);
    if (index == null || index < 0 || index >= target.profiles.length) {
      return null;
    }
    return target.profiles[index].id;
  }

  void _updateStatsDurationOnly(Duration duration) {
    _status(
      TunnelStatus.connected,
      mode: _activeMode,
      message: _connectedMessage(_activeMode ?? ConnectionMode.localProxy),
      stats: _current.stats.copyWithDuration(duration),
    );
  }

  Future<String?> _waitForOutboundInterface({
    int attempts = 8,
    String? previousInterface,
    bool waitForChange = false,
  }) async {
    String? lastCandidate;
    String? fallbackCandidate;
    var stableSamples = 0;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final value = await WindowsNetworkController.bestOutboundInterface();
        if (value != null && value.toLowerCase() != 'orexray') {
          if (value == lastCandidate) {
            stableSamples++;
          } else {
            lastCandidate = value;
            stableSamples = 1;
          }
          fallbackCandidate = value;

          final changed =
              previousInterface == null || value != previousInterface;
          if (stableSamples >= 2 && (!waitForChange || changed)) {
            return value;
          }
        }
      } catch (error) {
        _appendAppLog('Physical interface detection failed: $error');
      }
      if (attempt < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    // For a generic network notification the physical interface may remain the
    // same (DHCP renewals, address changes, metric updates). Return the stable
    // fallback only after the full settle window so callers can safely ignore
    // noise without missing a real Wi-Fi/Ethernet transition that appeared a
    // little later.
    return fallbackCandidate;
  }

  Future<int> _reserveLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<File> _prepareConfigFile({
    required XrayCoreInstall install,
    required bool elevated,
  }) async {
    if (elevated) {
      return File(p.join(install.directory.path, 'orexray-config.json'));
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'xray-runtime'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'orexray-config.json'));
  }

  String _proxyBypass({required bool includePrivateNetworks}) {
    if (!includePrivateNetworks) return _minimalProxyBypass;
    return '$_minimalProxyBypass;${_privateProxyBypass.join(';')}';
  }

  @override
  Future<void> stop() {
    _desiredTarget = null;
    _desiredMode = null;
    _restartBudget.reset();
    ++_operationId;
    final pending = _stopFuture;
    if (pending != null) return pending;

    late final Future<void> future;
    future = _stopInternal().whenComplete(() {
      if (_stopFuture == future) _stopFuture = null;
    });
    _stopFuture = future;
    return future;
  }

  Future<void> _stopInternal() async {
    _stopping = true;
    final process = _process;
    _appendAppLog(
      'Stop requested: PID=${process?.pid ?? 'none'}, '
      'mode=${(_activeMode ?? _current.mode).storageValue}.',
    );
    final mode = _activeMode ?? _current.mode;
    final wasActive = process != null ||
        _current.status == TunnelStatus.connecting ||
        _current.status == TunnelStatus.connected ||
        _current.status == TunnelStatus.error;

    if (wasActive) {
      _status(
        TunnelStatus.disconnecting,
        mode: mode,
        message: 'Останавливаем OrexRay…',
      );
    }
    _statsTimer?.cancel();
    _durationTimer?.cancel();
    await _closeStatsClient();

    try {
      try {
        await _proxyRecovery;
      } catch (error) {
        _appendAppLog('System proxy recovery failed: $error');
      }

      final pendingProxyEnable = _systemProxyEnableFuture;
      if (pendingProxyEnable != null) {
        try {
          await pendingProxyEnable;
        } catch (error) {
          _appendAppLog('System proxy enable failed during shutdown: $error');
        }
      }

      if (mode == ConnectionMode.systemProxy) {
        await _restoreSystemProxy();
      }

      if (process != null) {
        final stopped = await _terminateProcessTree(
          process,
          _managedExecutablePath ?? '',
        );
        if (!stopped) {
          _status(
            TunnelStatus.error,
            mode: mode,
            profile: _current.profile,
            error: 'Не удалось остановить Xray. Заверши OrexRay через трей '
                'или Диспетчер задач — системная привязка процесса остановит '
                'Xray вместе с приложением.',
            stats: const TrafficStats(),
          );
          return;
        }
        if (_process == process) _process = null;
      }

      _resetRuntimeState();
      _status(
        TunnelStatus.disconnected,
        mode: mode,
        stats: const TrafficStats(),
      );
      _activeMode = null;
      _appendAppLog('Connection stopped cleanly.');
    } finally {
      _stopping = false;
    }
  }

  Future<bool> _terminateProcessTree(
    Process process,
    String executablePath,
  ) async {
    try {
      process.kill();
    } catch (error) {
      _appendAppLog('Xray terminate failed: $error');
    }

    if (await _waitForExit(process, const Duration(seconds: 3))) {
      return true;
    }

    if (executablePath.isNotEmpty) {
      try {
        await WindowsProcessJob.terminateStaleProcesses(executablePath);
      } catch (error) {
        _appendAppLog('Native Xray cleanup failed: $error');
      }
    }

    return _waitForExit(process, const Duration(seconds: 2));
  }

  Future<bool> _waitForExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (error) {
      _appendAppLog('Could not observe Xray exit: $error');
      return false;
    }
  }

  void _resetRuntimeState() {
    _connectedAt = null;
    _statsPollInFlight = false;
    _lastStatsAt = null;
    _lastDownloadValue = null;
    _lastUploadValue = null;
    _managedExecutablePath = null;
    final configFile = _configFile;
    _configFile = null;
    if (configFile != null) {
      unawaited(
        configFile.delete().then<void>((_) {}).catchError((_) {}),
      );
    }
  }

  Future<void> _closeStatsClient() async {
    final client = _statsClient;
    _statsClient = null;
    if (client == null) return;
    try {
      await client.close();
    } catch (error) {
      _appendAppLog('Stats API shutdown failed: $error');
    }
  }

  Future<void> _restoreSystemProxy() async {
    try {
      await _systemProxy.restoreSaved();
    } catch (error) {
      _appendAppLog('System proxy restore failed: $error');
    }
  }

  String _startingMessage(ConnectionMode mode) => switch (mode) {
        ConnectionMode.vpnTun => 'Создаём VPN-интерфейс…',
        ConnectionMode.systemProxy => 'Запускаем локальный прокси…',
        ConnectionMode.localProxy => 'Запускаем локальный прокси…',
      };

  String _connectedMessage(ConnectionMode mode) => switch (mode) {
        ConnectionMode.vpnTun => 'VPN активен',
        ConnectionMode.systemProxy => 'Системный прокси активен',
        ConnectionMode.localProxy =>
          'SOCKS5 :${_settings.socksPort} · HTTP :${_settings.httpPort}',
      };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_operationId;

    if (_process != null ||
        _activeMode != null ||
        _current.status != TunnelStatus.disconnected) {
      await stop();
    } else {
      try {
        await _proxyRecovery;
      } catch (error) {
        _appendAppLog('System proxy recovery failed: $error');
      }
    }

    _statsTimer?.cancel();
    _durationTimer?.cancel();
    await _closeStatsClient();
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}
