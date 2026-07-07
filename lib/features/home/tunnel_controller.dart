import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/egress/egress_identity.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';

class TunnelController extends ChangeNotifier {
  TunnelController({
    required TunnelEngine engine,
    required ProfilesController profiles,
    required ConnectionSettingsController settings,
  })  : _engine = engine,
        _profiles = profiles,
        _settings = settings,
        _engineSnapshot = engine.current {
    _engineSubscription = _engine.snapshots.listen((value) {
      if (_closing) return;
      final becameConnected = value.isConnected && !_engineSnapshot.isConnected;
      _engineSnapshot = value;
      if (!value.isConnected && !value.isBusy) {
        _lastRuntimeMetadataKey = null;
      }
      if (value.isConnected) {
        _startEgressRefreshLoop();
      } else {
        _stopEgressRefreshLoop();
      }
      if (becameConnected) unawaited(refreshEgressIdentity(force: true));
      notifyListeners();
    });
    _profiles.addListener(_onDependencyChanged);
    _settings.addListener(_onDependencyChanged);
    unawaited(_loadEgressCache());
    if (_engineSnapshot.isConnected) {
      _startEgressRefreshLoop();
      unawaited(refreshEgressIdentity(force: true));
    }
  }

  final TunnelEngine _engine;
  final ProfilesController _profiles;
  final ConnectionSettingsController _settings;
  late final StreamSubscription<TunnelSnapshot> _engineSubscription;
  TunnelSnapshot _engineSnapshot;
  Future<void>? _shutdownFuture;
  Future<void>? _disposeFuture;
  Future<void>? _subscriptionCancelFuture;
  bool _dependenciesDetached = false;
  bool _closing = false;
  bool _disposed = false;
  String? _lastRuntimeMetadataKey;
  static const _egressCacheKey = 'orex_ray_egress_identity_v1';
  static const _egressRefreshInterval = Duration(minutes: 5);
  static const _egressRetryDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];
  final Map<String, EgressIdentity> _egressIdentities = {};
  final ValueNotifier<int> _egressRevision = ValueNotifier<int>(0);
  bool _egressRefreshInFlight = false;
  Timer? _egressRefreshTimer;

  Set<ConnectionMode> get supportedModes => {
        for (final mode in _settings.supportedModes)
          if (_engine.supportedModes.contains(mode)) mode,
      };

  ConnectionMode get mode => _settings.mode;

  bool get canChangeMode =>
      !_engineSnapshot.isBusy && !_engineSnapshot.isConnected;

  TunnelSnapshot get snapshot {
    if ((_engineSnapshot.isConnected || _engineSnapshot.isBusy) &&
        _engineSnapshot.profile != null) {
      final refreshed = _profiles.targetById(_engineSnapshot.profile!.id);
      return refreshed == null
          ? _engineSnapshot
          : _engineSnapshot.copyWith(profile: refreshed);
    }
    final selected = _profiles.selectedTarget;
    return _engineSnapshot.copyWith(
      mode: _settings.mode,
      profile: selected,
      clearProfile: selected == null,
    );
  }

  TunnelTarget? get selectedProfile => _profiles.selectedTarget;

  EgressIdentity? egressIdentityFor(String targetId) =>
      _egressIdentities[targetId];

  Listenable get egressChanges => _egressRevision;

  List<TunnelTarget> get targets => _profiles.targets;

  bool get refreshingLatency => _profiles.refreshingLatency;

  bool get canChangeTarget => !_engineSnapshot.isBusy;

  Future<void> selectTarget(String id) async {
    if (!canChangeTarget) return;
    final next = _profiles.targetById(id);
    if (next == null) return;

    final activeId = _engineSnapshot.profile?.id;
    final selectedId = _profiles.selectedTarget?.id;
    if (selectedId == id &&
        (!_engineSnapshot.isConnected || activeId == id)) {
      return;
    }

    final reconnect = _engineSnapshot.isConnected;
    final activeMode = _engineSnapshot.mode;
    if (reconnect) {
      await _engine.stop();
      _syncFromEngine();
    }

    await _profiles.select(id);

    if (reconnect) {
      final selected = _profiles.selectedTarget;
      if (selected != null) {
        await _engine.start(selected, activeMode);
        _syncFromEngine();
      }
    }
  }

  Future<void> refreshSelectedLatency() async {
    final target = _profiles.selectedTarget;
    if (target == null) return;
    for (final profile in target.profiles) {
      await _profiles.refreshLatency(profile.id);
    }
  }

  Future<void> setMode(ConnectionMode mode) async {
    if (!canChangeMode || !supportedModes.contains(mode)) return;
    await _settings.setMode(mode);
  }

  Future<void> toggle() async {
    if (_closing) return;
    final current = snapshot;
    if (current.isBusy) return;
    if (current.isConnected) {
      await disconnect();
      return;
    }
    await connect();
  }

  Future<void> connect() async {
    if (_closing) return;
    final current = snapshot;
    if (current.isBusy || current.isConnected) return;
    final profile = _profiles.selectedTarget;
    if (profile == null) {
      _engineSnapshot = current.copyWith(
        status: TunnelStatus.error,
        errorMessage: 'Сначала выбери профиль или балансировщик.',
      );
      notifyListeners();
      return;
    }
    await _engine.start(profile, _settings.mode);
    _syncFromEngine();
  }

  Future<void> disconnect() async {
    if (_closing) return;
    final current = snapshot;
    if (current.status == TunnelStatus.disconnected) return;
    await _engine.stop();
    _syncFromEngine();
  }

  Future<void> recover(TunnelRecoveryReason reason) async {
    if (_closing || !_engineSnapshot.isConnected) return;
    if (_engine case TunnelRecoverySink recovery) {
      await recovery.recover(reason);
      _syncFromEngine();
      if (_engineSnapshot.isConnected) {
        unawaited(refreshEgressIdentity(force: true));
      }
    }
  }

  bool get canReinstallXrayCore =>
      Platform.isWindows &&
      !_engineSnapshot.isBusy &&
      !_engineSnapshot.isConnected &&
      _engine is TunnelCoreMaintenance;

  Future<void> reinstallXrayCore({
    void Function(double progress)? onProgress,
  }) async {
    if (!canReinstallXrayCore) {
      throw StateError('Сначала отключи активное соединение.');
    }
    await (_engine as TunnelCoreMaintenance).reinstallCore(
      onProgress: onProgress,
    );
  }

  Future<TunnelDiagnostics> collectDiagnostics() async {
    if (_engine case TunnelDiagnosticsProvider provider) {
      return provider.collectDiagnostics();
    }
    return TunnelDiagnostics(
      platform: Platform.operatingSystem,
      xrayVersion: 'embedded',
      mode: snapshot.mode,
      targetName: snapshot.profile?.name ?? '—',
      xrayState: snapshot.status.name,
      pid: null,
      ports: {'SOCKS': _settings.socksPort, 'HTTP': _settings.httpPort},
      systemProxyStatus: 'not applicable',
      lastError: snapshot.errorMessage,
      lastExitCode: null,
      outboundInterface: null,
      routeSummary: 'not available',
      restartSummary: _settings.restartServiceOnKill ? 'enabled' : 'disabled',
      logs: const [],
    );
  }

  Future<void> refreshEgressIdentity({bool force = false}) async {
    if (_egressRefreshInFlight || !_engineSnapshot.isConnected) return;
    final target = _engineSnapshot.profile;
    if (target == null) return;
    final cached = _egressIdentities[target.id];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.checkedAt) <
            _egressRefreshInterval) {
      return;
    }
    if (_engineSnapshot.mode == ConnectionMode.vpnTun &&
        !_settings.localProxyInVpn) {
      return;
    }

    _egressRefreshInFlight = true;
    Object? lastError;
    try {
      _logDiagnostic(
        'Egress identity refresh started: mode=${_engineSnapshot.mode.storageValue}.',
      );
      for (var attempt = 0; attempt < _egressRetryDelays.length; attempt++) {
        if (!_isEgressTargetActive(target.id)) return;
        final delay = _egressRetryDelays[attempt];
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (!_isEgressTargetActive(target.id)) return;

        try {
          await _waitForEgressProxy();
          final identity = await _probeEgressIdentity();
          if (!_isEgressTargetActive(target.id)) return;
          _egressIdentities[target.id] = identity;
          await _saveEgressCache();
          _logDiagnostic(
            'Egress identity updated: country=${identity.countryCode}, '
            'WARP=${identity.warp ? 'on' : 'off'}.',
          );
          if (!_closing) _egressRevision.value++;
          return;
        } catch (error) {
          lastError = error;
          _logDiagnostic(
            'Egress identity attempt ${attempt + 1}/${_egressRetryDelays.length} '
            'failed: $error',
          );
        }
      }
      _logDiagnostic(
        'Egress identity refresh failed after ${_egressRetryDelays.length} '
        'attempts: ${lastError ?? 'unknown error'}. A periodic retry is scheduled.',
      );
    } finally {
      _egressRefreshInFlight = false;
    }
  }

  Future<void> _waitForEgressProxy({int attempts = 8}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _settings.httpPort,
          timeout: const Duration(milliseconds: 700),
        );
        socket.destroy();
        return;
      } catch (error) {
        lastError = error;
        socket?.destroy();
      }
      if (attempt < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw StateError(
      'Local HTTP proxy 127.0.0.1:${_settings.httpPort} is not ready: '
      '${lastError ?? 'connection failed'}',
    );
  }

  Future<EgressIdentity> _probeEgressIdentity() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 8)
      ..findProxy = (_) => 'PROXY 127.0.0.1:${_settings.httpPort}';
    try {
      final request = await client
          .getUrl(Uri.https('www.cloudflare.com', '/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Cloudflare trace returned HTTP ${response.statusCode}',
        );
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));
      if (body.length > 16 * 1024) {
        throw const FormatException('Cloudflare trace response is too large');
      }
      final identity = parseCloudflareTrace(body);
      if (identity == null) {
        throw const FormatException(
          'Cloudflare trace response has no valid country code',
        );
      }
      return identity;
    } finally {
      client.close(force: true);
    }
  }

  bool _isEgressTargetActive(String targetId) {
    return !_closing &&
        _engineSnapshot.isConnected &&
        _engineSnapshot.profile?.id == targetId;
  }

  void _startEgressRefreshLoop() {
    if (!Platform.isWindows || _egressRefreshTimer != null) return;
    _egressRefreshTimer = Timer.periodic(
      _egressRefreshInterval,
      (_) => unawaited(refreshEgressIdentity(force: true)),
    );
  }

  void _stopEgressRefreshLoop() {
    _egressRefreshTimer?.cancel();
    _egressRefreshTimer = null;
  }

  void _logDiagnostic(String message) {
    if (_engine case TunnelDiagnosticEventSink sink) {
      sink.addDiagnosticEvent(message);
    }
  }

  Future<void> _loadEgressCache() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_egressCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final identity = EgressIdentity.fromJson(entry.value);
        if (identity != null) _egressIdentities[entry.key.toString()] = identity;
      }
      if (!_closing) _egressRevision.value++;
    } catch (_) {
      await preferences.remove(_egressCacheKey);
    }
  }

  Future<void> _saveEgressCache() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _egressCacheKey,
      jsonEncode({for (final entry in _egressIdentities.entries) entry.key: entry.value.toJson()}),
    );
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
    _stopEgressRefreshLoop();
    _detachDependencies();
    await _cancelEngineSubscription();
    try {
      await _engine.stop();
    } finally {
      await _disposeEngine();
    }
  }

  Future<void> _disposeWithoutStopping() async {
    _closing = true;
    _stopEgressRefreshLoop();
    _detachDependencies();
    await _cancelEngineSubscription();
    await _disposeEngine();
  }

  Future<void> _cancelEngineSubscription() =>
      _subscriptionCancelFuture ??= _engineSubscription.cancel();

  Future<void> _disposeEngine() => _disposeFuture ??= _engine.dispose();

  void _syncFromEngine() {
    _engineSnapshot = _engine.current;
    if (!_closing) notifyListeners();
  }

  void _detachDependencies() {
    if (_dependenciesDetached) return;
    _dependenciesDetached = true;
    _profiles.removeListener(_onDependencyChanged);
    _settings.removeListener(_onDependencyChanged);
  }

  void _onDependencyChanged() {
    if (_closing) return;
    final active = _engineSnapshot.profile;
    if ((_engineSnapshot.isConnected || _engineSnapshot.isBusy) &&
        active != null &&
        _engine is TunnelRuntimeMetadataSink) {
      final refreshed = _profiles.targetById(active.id);
      if (refreshed != null) {
        final metadataKey = _runtimeMetadataKey(refreshed);
        if (metadataKey != _lastRuntimeMetadataKey) {
          _lastRuntimeMetadataKey = metadataKey;
          unawaited(
            (_engine as TunnelRuntimeMetadataSink).updateTargetMetadata(refreshed),
          );
        }
      }
    }
    notifyListeners();
  }


  String _runtimeMetadataKey(TunnelTarget target) =>
      '${target.id}\u0000${target.name}\u0000${target.latencyMs ?? -1}';

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    _stopEgressRefreshLoop();
    _detachDependencies();
    _egressRevision.dispose();
    unawaited(_shutdownFuture ??= _disposeWithoutStopping());
    super.dispose();
  }
}
