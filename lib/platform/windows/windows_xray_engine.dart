import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../core/xray/xray_config_builder.dart';
import 'windows_system_proxy_controller.dart';
import 'xray_core_manager.dart';

class WindowsXrayEngine implements TunnelEngine {
  WindowsXrayEngine({
    required ConnectionSettingsController settings,
    XrayCoreManager? coreManager,
    XrayConfigBuilder? configBuilder,
    WindowsSystemProxyController? systemProxyController,
  })  : _settings = settings,
        _coreManager = coreManager ?? XrayCoreManager(),
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
  Process? _process;
  Timer? _statsTimer;
  DateTime? _connectedAt;
  int? _baseDownload;
  int? _baseUpload;
  TunnelSnapshot _current;
  ConnectionMode? _activeMode;
  bool _stopping = false;

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
    TunnelProfile? profile,
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

  @override
  Future<void> start(TunnelProfile profile, ConnectionMode mode) async {
    if (_process != null || _current.isBusy || _current.isConnected) return;
    if (!supportedModes.contains(mode)) {
      _status(
        TunnelStatus.error,
        mode: mode,
        profile: profile,
        error: 'Этот режим не поддерживается в Windows.',
      );
      return;
    }

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
      final install = await _coreManager.ensureInstalled(
        onProgress: (progress) {
          _status(
            TunnelStatus.connecting,
            mode: mode,
            profile: profile,
            message: 'Скачиваем Xray Core · ${(progress * 100).round()}%',
            stats: const TrafficStats(),
          );
        },
      );

      final configFile = File(p.join(install.directory.path, 'orexray-config.json'));
      final config = switch (mode) {
        ConnectionMode.vpnTun => _configBuilder.buildWindowsTun(
            profile,
            mtu: _settings.mtu,
            dnsServers: _settings.dnsServers,
            bypassPrivateNetworks: _settings.bypassPrivateNetworks,
            sniffingEnabled: _settings.sniffingEnabled,
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
            logLevel: _settings.logLevel,
          ),
      };
      await configFile.writeAsString(config, flush: true);

      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: 'Проверяем конфигурацию…',
      );
      await _validateConfig(install, configFile);

      _status(
        TunnelStatus.connecting,
        mode: mode,
        profile: profile,
        message: _startingMessage(mode),
      );
      final process = await Process.start(
        install.executable.path,
        ['run', '-c', configFile.path],
        workingDirectory: install.directory.path,
        mode: ProcessStartMode.normal,
      );
      _process = process;
      _listenLogs(process);

      final earlyExit = await Future.any<int?>([
        process.exitCode.then<int?>((value) => value),
        Future<int?>.delayed(const Duration(milliseconds: 900), () => null),
      ]);
      if (earlyExit != null) {
        _process = null;
        throw StateError(_bestError('Xray завершился с кодом $earlyExit'));
      }

      if (mode == ConnectionMode.systemProxy) {
        _status(
          TunnelStatus.connecting,
          mode: mode,
          profile: profile,
          message: 'Включаем системный прокси Windows…',
        );
        await _systemProxy.enable(
          server: '127.0.0.1:${_settings.httpPort}',
          bypass: _proxyBypass,
        );
      }

      _connectedAt = DateTime.now();
      _baseDownload = null;
      _baseUpload = null;
      _status(
        TunnelStatus.connected,
        mode: mode,
        profile: profile,
        message: _connectedMessage(mode),
        stats: const TrafficStats(),
      );
      _startStats();

      unawaited(process.exitCode.then((code) async {
        if (_stopping || _snapshots.isClosed) return;
        _process = null;
        _statsTimer?.cancel();
        if (_activeMode == ConnectionMode.systemProxy) {
          await _restoreSystemProxy();
        }
        _status(
          code == 0 ? TunnelStatus.disconnected : TunnelStatus.error,
          mode: mode,
          profile: profile,
          error: code == 0 ? null : _bestError('Xray завершился с кодом $code'),
          stats: const TrafficStats(),
        );
      }));
    } catch (error) {
      _process?.kill();
      _process = null;
      _statsTimer?.cancel();
      if (mode == ConnectionMode.systemProxy) {
        await _restoreSystemProxy();
      }
      _status(
        TunnelStatus.error,
        mode: mode,
        profile: profile,
        error: _friendlyError(error, mode),
        stats: const TrafficStats(),
      );
    }
  }

  Future<void> _validateConfig(
    XrayCoreInstall install,
    File configFile,
  ) async {
    final result = await Process.run(
      install.executable.path,
      ['run', '-test', '-c', configFile.path],
      workingDirectory: install.directory.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final output = '${result.stderr}\n${result.stdout}'.trim();
      throw FormatException(
        output.isEmpty ? 'Xray отклонил конфигурацию.' : output,
      );
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
      _status(
        TunnelStatus.connected,
        mode: ConnectionMode.vpnTun,
        message: _connectedMessage(ConnectionMode.vpnTun),
        stats: TrafficStats(
          downloadBytes: received - _baseDownload!,
          uploadBytes: sent - _baseUpload!,
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
  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      await _restoreSystemProxy();
      _status(
        TunnelStatus.disconnected,
        mode: _activeMode,
        stats: const TrafficStats(),
      );
      return;
    }

    _stopping = true;
    _status(
      TunnelStatus.disconnecting,
      mode: _activeMode,
      message: 'Останавливаем OrexRay…',
    );
    _statsTimer?.cancel();

    if (_activeMode == ConnectionMode.systemProxy) {
      await _restoreSystemProxy();
    }

    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    }
    _process = null;
    _connectedAt = null;
    _baseDownload = null;
    _baseUpload = null;
    _status(
      TunnelStatus.disconnected,
      mode: _activeMode,
      stats: const TrafficStats(),
    );
    _activeMode = null;
    _stopping = false;
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
          'SOCKS5 :${XrayConfigBuilder.socksPort} · HTTP :${XrayConfigBuilder.httpPort}',
      };

  @override
  Future<void> dispose() async {
    _statsTimer?.cancel();
    if (_activeMode == ConnectionMode.systemProxy) {
      await _restoreSystemProxy();
    }
    _process?.kill();
    await _snapshots.close();
  }
}

extension on TrafficStats {
  TrafficStats copyWithDuration(Duration duration) {
    return TrafficStats(
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      duration: duration,
    );
  }
}
