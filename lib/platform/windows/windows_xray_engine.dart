import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_version.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../core/xray/xray_config_builder.dart';
import 'windows_process_job.dart';
import 'windows_system_proxy_controller.dart';
import 'xray_core_manager.dart';

class WindowsXrayEngine implements TunnelEngine {
  WindowsXrayEngine({
    required ConnectionSettingsController settings,
    OrexAppVersion appVersion = OrexAppVersion.fallback,
    XrayCoreManager? coreManager,
    XrayConfigBuilder? configBuilder,
    WindowsSystemProxyController? systemProxyController,
  })  : _settings = settings,
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

  static const _proxyBypass =
      '<local>;localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;'
      '172.2*;172.3*;192.168.*';

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
  DateTime? _connectedAt;
  int? _baseDownload;
  int? _baseUpload;
  DateTime? _lastStatsAt;
  int? _lastDownloadValue;
  int? _lastUploadValue;
  TunnelSnapshot _current;
  ConnectionMode? _activeMode;
  bool _stopping = false;
  bool _disposed = false;
  int _operationId = 0;

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
  }) {
    _emit(TunnelSnapshot(
      status: status,
      mode: mode ?? _current.mode,
      profile: profile ?? _current.profile,
      stats: stats ?? _current.stats,
      message: message,
      errorMessage: error,
    ));
  }

  bool _isCurrentOperation(int operationId) =>
      !_disposed && operationId == _operationId;

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    if (_disposed ||
        _process != null ||
        _current.isBusy ||
        _current.isConnected) {
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
    _logs.clear();
    _activeMode = mode;
    _status(
      TunnelStatus.connecting,
      mode: mode,
      profile: profile,
      message: 'Подготавливаем Xray Core…',
      stats: const TrafficStats(),
    );

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

      // Recover from old OrexRay versions that could leave their managed
      // xray.exe alive after the Flutter process exited. The native side only
      // terminates processes whose full executable path exactly matches this
      // OrexRay-managed core path.
      await WindowsProcessJob.terminateStaleProcesses(install.executable.path);
      if (!_isCurrentOperation(operationId)) return;

      final configFile =
          File(p.join(install.directory.path, 'orexray-config.json'));
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
      await _validateConfig(install, configFile);
      if (!_isCurrentOperation(operationId)) return;

      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: _startingMessage(mode),
      );
      startedProcess = await Process.start(
        install.executable.path,
        ['run', '-c', configFile.path],
        workingDirectory: install.directory.path,
        mode: ProcessStartMode.normal,
      );
      _process = startedProcess;
      _listenLogs(startedProcess);

      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess);
        if (_process == startedProcess) _process = null;
        return;
      }

      // Make Xray an OS-owned child of OrexRay before treating it as started.
      // Closing the OrexRay process then kills Xray even after a crash or a
      // forced process termination that bypasses Dart cleanup.
      await WindowsProcessJob.attach(startedProcess.pid);
      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess);
        if (_process == startedProcess) _process = null;
        return;
      }

      final earlyExit = await Future.any<int?>([
        startedProcess.exitCode.then<int?>((value) => value),
        Future<int?>.delayed(const Duration(milliseconds: 900), () => null),
      ]);
      if (!_isCurrentOperation(operationId)) {
        await _terminateProcessTree(startedProcess);
        if (_process == startedProcess) _process = null;
        return;
      }
      if (earlyExit != null) {
        if (_process == startedProcess) _process = null;
        throw StateError(_bestError('Xray завершился с кодом $earlyExit'));
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
              bypass: _proxyBypass,
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
        if (!_isCurrentOperation(operationId)) {
          await _restoreSystemProxy();
          await _terminateProcessTree(startedProcess);
          if (_process == startedProcess) _process = null;
          return;
        }
      }

      _connectedAt = DateTime.now();
      _baseDownload = null;
      _baseUpload = null;
      _lastStatsAt = null;
      _lastDownloadValue = null;
      _lastUploadValue = null;
      _status(
        TunnelStatus.connected,
        mode: mode,
        profile: profile,
        message: _connectedMessage(mode),
        stats: const TrafficStats(),
      );
      _startStats();

      unawaited(startedProcess.exitCode.then((code) async {
        if (_process != startedProcess ||
            _stopping ||
            _snapshots.isClosed) {
          return;
        }
        _process = null;
        _statsTimer?.cancel();
        if (_activeMode == ConnectionMode.systemProxy) {
          await _restoreSystemProxy();
        }
        _resetRuntimeState();
        _status(
          code == 0 ? TunnelStatus.disconnected : TunnelStatus.error,
          mode: mode,
          profile: profile,
          error: code == 0
              ? null
              : _bestError('Xray завершился с кодом $code'),
          stats: const TrafficStats(),
        );
        _activeMode = null;
      }));
    } catch (error) {
      final canceled = !_isCurrentOperation(operationId);
      final process = startedProcess;
      if (process != null) {
        await _terminateProcessTree(process);
        if (_process == process) _process = null;
      }
      _statsTimer?.cancel();
      if (mode == ConnectionMode.systemProxy) {
        await _restoreSystemProxy();
      }
      _resetRuntimeState();

      if (!canceled && !_disposed) {
        _status(
          TunnelStatus.error,
          mode: mode,
          profile: profile,
          error: _friendlyError(error, mode),
          stats: const TrafficStats(),
        );
      }
      if (_activeMode == mode) _activeMode = null;
    }
  }

  Future<void> _validateConfig(
    XrayCoreInstall install,
    File configFile,
  ) async {
    final process = await Process.start(
      install.executable.path,
      ['run', '-test', '-c', configFile.path],
      workingDirectory: install.directory.path,
      mode: ProcessStartMode.normal,
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
      await _terminateProcessTree(process);
      rethrow;
    } finally {
      if (_process == process) _process = null;
    }
  }

  void _listenLogs(Process process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
  }

  void _appendLog(String line) {
    final clean = line.trim();
    if (clean.isEmpty) return;
    _logs.add(clean);
    if (_logs.length > 80) _logs.removeAt(0);
  }

  String _bestError(String fallback) {
    for (final line in _logs.reversed) {
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

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollStats());
    });
    unawaited(_pollStats());
  }

  Future<void> _pollStats() async {
    if (_process == null || _connectedAt == null) return;
    final duration = DateTime.now().difference(_connectedAt!);

    if (_activeMode != ConnectionMode.vpnTun) {
      _status(
        TunnelStatus.connected,
        mode: _activeMode,
        message: _connectedMessage(_activeMode ?? ConnectionMode.localProxy),
        stats: _current.stats.copyWithDuration(duration),
      );
      return;
    }

    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$s=Get-NetAdapterStatistics -Name 'OrexRay' -ErrorAction Stop; Write-Output ($s.ReceivedBytes.ToString()+'|'+$s.SentBytes.ToString())",
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) return;
      final parts = result.stdout.toString().trim().split('|');
      if (parts.length != 2) return;
      final received = int.tryParse(parts[0]);
      final sent = int.tryParse(parts[1]);
      if (received == null || sent == null) return;
      _baseDownload ??= received;
      _baseUpload ??= sent;
      final download = received - _baseDownload!;
      final upload = sent - _baseUpload!;
      final now = DateTime.now();
      final seconds = _lastStatsAt == null
          ? 0.0
          : now.difference(_lastStatsAt!).inMilliseconds / 1000.0;
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
        mode: ConnectionMode.vpnTun,
        message: _connectedMessage(ConnectionMode.vpnTun),
        stats: TrafficStats(
          downloadBytes: download,
          uploadBytes: upload,
          downloadBytesPerSecond: downBps,
          uploadBytesPerSecond: upBps,
          duration: duration,
        ),
      );
    } catch (_) {
      _status(
        TunnelStatus.connected,
        mode: ConnectionMode.vpnTun,
        message: _connectedMessage(ConnectionMode.vpnTun),
        stats: _current.stats.copyWithDuration(duration),
      );
    }
  }

  @override
  Future<void> stop() {
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

    try {
      try {
        await _proxyRecovery;
      } catch (error) {
        _appendLog('System proxy recovery failed: $error');
      }

      final pendingProxyEnable = _systemProxyEnableFuture;
      if (pendingProxyEnable != null) {
        try {
          await pendingProxyEnable;
        } catch (error) {
          _appendLog('System proxy enable failed during shutdown: $error');
        }
      }

      if (mode == ConnectionMode.systemProxy) {
        await _restoreSystemProxy();
      }

      if (process != null) {
        final stopped = await _terminateProcessTree(process);
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
    } finally {
      _stopping = false;
    }
  }

  Future<bool> _terminateProcessTree(Process process) async {
    try {
      process.kill();
    } catch (error) {
      _appendLog('Xray terminate failed: $error');
    }

    if (await _waitForExit(process, const Duration(seconds: 3))) {
      return true;
    }

    try {
      final result = await Process.run(
        'taskkill',
        ['/PID', '${process.pid}', '/T', '/F'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final output = '${result.stderr}\n${result.stdout}'.trim();
        if (output.isNotEmpty) _appendLog(output);
      }
    } catch (error) {
      _appendLog('taskkill failed: $error');
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
      _appendLog('Could not observe Xray exit: $error');
      return false;
    }
  }

  void _resetRuntimeState() {
    _connectedAt = null;
    _baseDownload = null;
    _baseUpload = null;
    _lastStatsAt = null;
    _lastDownloadValue = null;
    _lastUploadValue = null;
  }

  Future<void> _restoreSystemProxy() async {
    try {
      await _systemProxy.restoreSaved();
    } catch (error) {
      _appendLog('System proxy restore failed: $error');
    }
  }

  String _startingMessage(ConnectionMode mode) => switch (mode) {
        ConnectionMode.vpnTun => 'Создаём VPN-интерфейс…',
        ConnectionMode.systemProxy => 'Запускаем локальный прокси…',
        ConnectionMode.localProxy => 'Запускаем локальный прокси…',
      };

  String _connectedMessage(ConnectionMode mode) => switch (mode) {
        ConnectionMode.vpnTun => 'VPN-туннель активен',
        ConnectionMode.systemProxy => 'Системный прокси Windows активен',
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
        _appendLog('System proxy recovery failed: $error');
      }
    }

    _statsTimer?.cancel();
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}
