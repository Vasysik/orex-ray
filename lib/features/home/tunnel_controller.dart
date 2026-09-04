import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/egress/egress_identity.dart';
import '../../core/egress/exit_location_refresh_coordinator.dart';
import '../../core/profiles/latency_probe.dart';
import '../../core/profiles/profiles_controller.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';

class TunnelController extends ChangeNotifier {
  TunnelController({
    required TunnelEngine engine,
    required ProfilesController profiles,
    required ConnectionSettingsController settings,
    ExitLocationRefreshPolicy? egressRefreshPolicy,
    TunnelRouteLatencyProbe? routeLatencyProbe,
    Duration routeProbeStartupDelay = const Duration(milliseconds: 350),
  })  : _engine = engine,
        _profiles = profiles,
        _settings = settings,
        _routeLatencyProbe = routeLatencyProbe ?? TunnelRouteLatencyProbe(),
        _routeProbeStartupDelay = routeProbeStartupDelay,
        _engineSnapshot = engine.current {
    _egressRefreshCoordinator = ExitLocationRefreshCoordinator(
      policy: egressRefreshPolicy ??
          ExitLocationRefreshPolicy.forOperatingSystem(
              Platform.operatingSystem),
      activeTargetId: () =>
          _engineSnapshot.isConnected ? _engineSnapshot.profile?.id : null,
      canRefresh: _canRefreshEgressTarget,
      refresh: _refreshEgressIdentity,
    );
    _engineSubscription = _engine.snapshots.listen((value) {
      if (_closing) return;
      // `start()` also synchronizes from `engine.current`.  Some engines emit
      // their queued "connecting" event after that synchronous state has
      // already advanced to connected; accepting it would invalidate a valid
      // route probe and schedule a second one.
      if (_engineSnapshot.isConnected &&
          value.status == TunnelStatus.connecting &&
          value.mode == _engineSnapshot.mode &&
          value.profile?.id == _engineSnapshot.profile?.id) {
        return;
      }
      final previous = _engineSnapshot;
      final becameConnected = value.isConnected && !previous.isConnected;
      if (_latencyContextChanged(previous, value)) {
        _latencyContextRevision++;
      }
      if (previous.isConnected &&
          previous.mode == ConnectionMode.vpnTun &&
          !value.isConnected) {
        _pendingVpnDirectLatencyTargetId = previous.profile?.id;
      }
      if (value.isConnected) {
        _pendingVpnDirectLatencyTargetId = null;
      }
      _engineSnapshot = value;
      _clearRouteLatencyIfStale();
      _adoptNativeRouteHealth(value);
      if (!value.isConnected && !value.isBusy) {
        _lastRuntimeMetadataKey = null;
      }
      if (value.isConnected) {
        _egressRefreshCoordinator.startPeriodic();
      } else {
        _egressRefreshCoordinator.stopPeriodic();
      }
      if (becameConnected) {
        _handleBecameConnected(value);
      }
      final disconnectedVpnTargetId = value.status == TunnelStatus.disconnected
          ? _pendingVpnDirectLatencyTargetId
          : null;
      if (disconnectedVpnTargetId != null) {
        _schedulePendingVpnDirectLatency(disconnectedVpnTargetId);
      }
      notifyListeners();
    });
    _lastSelectedTargetId = _profiles.selectedTarget?.id;
    _lastConfiguredMode = _settings.mode;
    _lastRouteProbeUri = _settings.latencyProbeUri;
    _profiles.addListener(_onProfilesChanged);
    _settings.addListener(_onSettingsChanged);
    unawaited(_loadEgressCache());
    if (_engineSnapshot.isConnected) {
      _adoptNativeRouteHealth(_engineSnapshot);
      _hasConnectedBefore = true;
      _egressRefreshCoordinator.startPeriodic();
      unawaited(_requestEgressRefresh(ExitLocationRefreshTrigger.connected));
    }
  }

  final TunnelEngine _engine;
  final ProfilesController _profiles;
  final ConnectionSettingsController _settings;
  final TunnelRouteLatencyProbe _routeLatencyProbe;
  final Duration _routeProbeStartupDelay;
  late final StreamSubscription<TunnelSnapshot> _engineSubscription;
  TunnelSnapshot _engineSnapshot;
  Future<void>? _shutdownFuture;
  Future<void>? _disposeFuture;
  Future<void>? _subscriptionCancelFuture;
  bool _dependenciesDetached = false;
  bool _closing = false;
  bool _disposed = false;
  bool _hasConnectedBefore = false;
  int _latencyContextRevision = 0;
  String? _lastSelectedTargetId;
  ConnectionMode? _lastConfiguredMode;
  String? _pendingVpnDirectLatencyTargetId;
  Future<void>? _automaticRouteLatencyFuture;
  int? _automaticRouteLatencyContextRevision;
  int? _automaticRouteLatencyProbeConfigurationRevision;
  String? _lastRuntimeMetadataKey;
  static const _egressCacheKey = 'orex_ray_egress_identity_v1';
  static const _egressRetryDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];
  final Map<String, EgressIdentity> _egressIdentities = {};
  final ValueNotifier<int> _egressRevision = ValueNotifier<int>(0);
  late final ExitLocationRefreshCoordinator _egressRefreshCoordinator;
  LatencyProbeResult? _activeRouteLatency;
  String? _activeRouteLatencyTargetId;
  int _routeLatencyRefreshCount = 0;
  late Uri _lastRouteProbeUri;
  int _routeProbeConfigurationRevision = 0;

  Set<ConnectionMode> get supportedModes => {
        for (final mode in _settings.supportedModes)
          if (_engine.supportedModes.contains(mode)) mode,
      };

  ConnectionMode get mode => _settings.mode;

  bool get canChangeMode =>
      !_engineSnapshot.isBusy && !_engineSnapshot.isConnected;

  TunnelSnapshot get snapshot {
    if (_engineSnapshot.isConnected || _engineSnapshot.isBusy) {
      final active = _engineSnapshot.profile;
      // A native Android VPN can outlive a Flutter activity. Until its stable
      // target id has been restored, presenting the selected profile here
      // would expose that profile's saved direct ping as if it were the live
      // VPN route. Keep the active target unknown instead.
      if (active == null) return _engineSnapshot;
      final refreshed = _profiles.targetById(active.id);
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

  /// The most recent manual end-to-end measurement for the active Xray route.
  /// It includes the selected cascade/balancer and is not persisted as a
  /// profile's direct TCP reachability result.
  LatencyProbeResult? routeLatencyFor(String targetId) =>
      _activeRouteLatencyTargetId == targetId && _engineSnapshot.isConnected
          ? _activeRouteLatency
          : null;

  /// The latency that belongs in the existing home ping field.
  ///
  /// While connected this is the end-to-end route measurement for the active
  /// target. A direct TCP connection is a different metric and, in VPN mode,
  /// can be captured recursively by the TUN. Non-active targets keep their
  /// saved direct value for the existing list UI, but are not refreshed while
  /// a route is active.
  int? effectiveLatencyFor(TunnelTarget? target) {
    if (target == null) return null;
    if (_engineSnapshot.isConnected) {
      if (_isActiveRouteTarget(target.id)) {
        final routeLatency = routeLatencyFor(target.id);
        if (routeLatency != null) return routeLatency.latencyMs;
        return _engineSnapshot.effectivePingStatus == PingStatus.success
            ? _engineSnapshot.effectiveLatencyMs
            : null;
      }
      return target.latencyMs;
    }
    final routeLatency = routeLatencyFor(target.id);
    return routeLatency == null ? target.latencyMs : routeLatency.latencyMs;
  }

  /// Matches [effectiveLatencyFor] for state consumers such as the existing
  /// global status pill and the Windows tray icon. In an active VPN a saved
  /// direct result is deliberately not a fallback: it could have been
  /// measured recursively through the TUN.
  PingStatus effectivePingStatusFor(TunnelTarget? target) {
    if (target == null) return PingStatus.unknown;
    if (_engineSnapshot.isConnected) {
      if (_isActiveRouteTarget(target.id)) {
        return routeLatencyFor(target.id)?.status ??
            _engineSnapshot.effectivePingStatus;
      }
      return _engineSnapshot.mode == ConnectionMode.vpnTun
          ? PingStatus.unknown
          : target.pingStatus;
    }
    final routeLatency = routeLatencyFor(target.id);
    return routeLatency?.status ?? target.pingStatus;
  }

  Listenable get egressChanges => _egressRevision;

  List<TunnelTarget> get targets => _profiles.targets;

  bool get refreshingLatency =>
      _profiles.refreshingLatency || _routeLatencyRefreshCount > 0;

  bool get canChangeTarget => !_engineSnapshot.isBusy;

  /// Waits for a native runtime that may have survived the Flutter activity,
  /// then adopts its current snapshot before latency or connection decisions.
  Future<void> waitForInitialState() async {
    if (_closing) return;
    if (_engine case TunnelInitialStateSync synchronizer) {
      await synchronizer.waitForInitialState();
      if (_closing) return;
      _syncFromEngine();
    }
  }

  /// Direct TCP checks belong to the profile list, while the home screen has
  /// its own end-to-end route metric. A VPN only permits list checks when the
  /// selected probe explicitly proves it bypasses OrexRay's TUN; otherwise a
  /// raw socket could produce a recursive 1–4 ms pseudo-ping.
  bool canRefreshTargetLatency(String targetId) {
    if (_engineSnapshot.isBusy) return false;
    if (_profiles.targetById(targetId) == null) return false;
    return _canRefreshSavedDirectLatencies ||
        (_engineSnapshot.isConnected &&
            _engineSnapshot.profile?.id == targetId);
  }

  /// Performs the one event-driven check requested when the application is
  /// opened. It deliberately checks only the selected target, never every
  /// saved profile.
  Future<void> refreshLatencyOnAppOpen() async {
    if (_closing) return;
    await waitForInitialState();
    if (_closing) return;
    final current = _engineSnapshot;
    final contextRevision = _latencyContextRevision;
    if (current.isConnected) {
      await _refreshRouteLatencyForLifecycle(
        expectedTargetId: current.profile?.id,
        waitForProxy: true,
      );
      return;
    }
    if (!current.isBusy) {
      final target = _profiles.selectedTarget;
      if (target != null) {
        await _refreshDirectTargetLatency(
          target.id,
          expectedContextRevision: contextRevision,
          requireSelectedTarget: true,
        );
      }
    }
  }

  Future<void> selectTarget(String id) async {
    if (!canChangeTarget) return;
    final next = _profiles.targetById(id);
    if (next == null) return;

    final activeId = _engineSnapshot.profile?.id;
    final selectedId = _profiles.selectedTarget?.id;
    if (selectedId == id && (!_engineSnapshot.isConnected || activeId == id)) {
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
    await waitForInitialState();
    if (_closing) return;
    // A native Android VPN may outlive Flutter's activity. Its restored route
    // can differ from the locally saved selection, and the visible home card
    // represents that active route. Refresh it instead of silently no-oping.
    final target = _engineSnapshot.isConnected
        ? _engineSnapshot.profile
        : _profiles.selectedTarget;
    if (target == null) return;
    // The home card always represents the active route, never the profile
    // list's direct endpoint result. In particular, this must stay true on
    // Android and Windows where list probes can safely bypass an active TUN.
    if (_engineSnapshot.isConnected) {
      await _refreshActiveRouteLatency(expectedTargetId: target.id);
      return;
    }
    await _refreshDirectTargetLatency(target.id);
  }

  /// Refreshes the saved direct TCP result shown in the profile list. The
  /// connected target's end-to-end measurement remains exclusively on the
  /// home card via [refreshSelectedLatency].
  Future<void> refreshTargetLatency(String targetId) async {
    await waitForInitialState();
    if (_closing) return;
    final target = _profiles.targetById(targetId);
    if (target == null) return;
    if (_engineSnapshot.isConnected && !_canRefreshSavedDirectLatencies) {
      if (_isActiveRouteTarget(target.id)) {
        await _refreshActiveRouteLatency(expectedTargetId: target.id);
      }
      return;
    }
    await _refreshDirectTargetLatency(target.id);
  }

  Future<void> refreshProfileLatency(String profileId) async {
    await waitForInitialState();
    if (_closing) return;
    final active = _engineSnapshot.profile;
    if (_engineSnapshot.isConnected && !_canRefreshSavedDirectLatencies) {
      if (active?.id == profileId) {
        await _refreshActiveRouteLatency(expectedTargetId: active?.id);
      }
      return;
    }
    final contextRevision = _latencyContextRevision;
    await _profiles.refreshLatency(
      profileId,
      shouldApply: () => _canApplyDirectLatency(contextRevision),
    );
  }

  Future<void> refreshProfileLatencies(Iterable<String> profileIds) async {
    await waitForInitialState();
    if (_closing) return;
    final ids = profileIds.toSet();
    if (ids.isEmpty) return;
    final active = _engineSnapshot.profile;
    if (_engineSnapshot.isConnected && !_canRefreshSavedDirectLatencies) {
      if (active != null &&
          !active.isBalancer &&
          ids.contains(active.primaryProfile.id)) {
        await _refreshActiveRouteLatency(expectedTargetId: active.id);
      }
      return;
    }
    final contextRevision = _latencyContextRevision;
    await _profiles.refreshLatencies(
      ids,
      shouldApply: () => _canApplyDirectLatency(contextRevision),
    );
  }

  Future<void> refreshAllLatencies() async {
    await waitForInitialState();
    if (_closing) return;
    final active = _engineSnapshot.profile;
    if (_engineSnapshot.isConnected &&
        !_canRefreshSavedDirectLatencies &&
        active != null) {
      await _refreshActiveRouteLatency(expectedTargetId: active.id);
      return;
    }
    final contextRevision = _latencyContextRevision;
    await _profiles.refreshAllLatencies(
      shouldApply: () => _canApplyDirectLatency(contextRevision),
    );
  }

  Future<void> setMode(ConnectionMode mode) async {
    if (!canChangeMode || !supportedModes.contains(mode)) return;
    await _settings.setMode(mode);
  }

  Future<void> toggle() async {
    if (_closing) return;
    await waitForInitialState();
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
    await waitForInitialState();
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
    await waitForInitialState();
    if (_closing) return;
    final current = snapshot;
    if (current.status == TunnelStatus.disconnected) return;
    if (current.isConnected && current.mode == ConnectionMode.vpnTun) {
      _pendingVpnDirectLatencyTargetId = current.profile?.id;
    }
    await _engine.stop();
    _syncFromEngine();
    if (_engineSnapshot.status == TunnelStatus.disconnected) {
      final targetId = _pendingVpnDirectLatencyTargetId;
      if (targetId != null) _schedulePendingVpnDirectLatency(targetId);
    }
  }

  Future<void> recover(TunnelRecoveryReason reason) async {
    if (_closing || !_engineSnapshot.isConnected) return;
    if (_engine case TunnelRecoverySink recovery) {
      await recovery.recover(reason);
      _syncFromEngine();
      if (_engineSnapshot.isConnected) {
        unawaited(
          _requestEgressRefresh(ExitLocationRefreshTrigger.networkRecovered),
        );
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

  /// Requests a manual exit-location refresh for the currently active target.
  /// The coordinator owns de-duplication and platform policy.
  Future<void> refreshEgressIdentity() =>
      _requestEgressRefresh(ExitLocationRefreshTrigger.diagnostics);

  Future<void> _requestEgressRefresh(ExitLocationRefreshTrigger trigger) {
    final targetId = _engineSnapshot.profile?.id;
    if (targetId == null) return Future<void>.value();
    return _egressRefreshCoordinator.request(targetId, trigger: trigger);
  }

  Future<void> _refreshEgressIdentity(
    String targetId,
    ExitLocationRefreshTrigger trigger,
  ) async {
    final target = _engineSnapshot.profile;
    if (target == null || target.id != targetId) return;
    Object? lastError;
    _logDiagnostic(
      'Egress identity refresh started: trigger=${trigger.name}, '
      'mode=${_engineSnapshot.mode.storageValue}.',
    );
    for (var attempt = 0; attempt < _egressRetryDelays.length; attempt++) {
      if (!_canRefreshEgressTarget(target.id, trigger)) return;
      final delay = _egressRetryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!_canRefreshEgressTarget(target.id, trigger)) return;

      try {
        await _waitForEgressProxy();
        final identity = await _probeEgressIdentity();
        if (!_canRefreshEgressTarget(target.id, trigger)) return;
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
      'attempts: ${lastError ?? 'unknown error'}.',
    );
  }

  /// Measures the already-active Xray route through its loopback HTTP inbound.
  /// The loopback hop is only the entry into Xray; the probe completes a
  /// remote TLS handshake (or HTTP header check for a custom HTTP endpoint),
  /// so the result includes the chosen outbound/cascade rather than a local
  /// socket acknowledgement.
  Future<void> _refreshActiveRouteLatency({
    String? expectedTargetId,
    int? expectedContextRevision,
    int? expectedProbeConfigurationRevision,
    bool waitForProxy = false,
  }) async {
    final target = _engineSnapshot.profile;
    final targetId = expectedTargetId ?? target?.id;
    final contextRevision = expectedContextRevision ?? _latencyContextRevision;
    final probeConfigurationRevision =
        expectedProbeConfigurationRevision ?? _routeProbeConfigurationRevision;
    if (target == null ||
        targetId == null ||
        !_canApplyRouteLatency(
          targetId,
          contextRevision,
          probeConfigurationRevision,
        )) {
      return;
    }

    _routeLatencyRefreshCount++;
    notifyListeners();
    try {
      // Android reports the connection immediately after Xray starts. Give the
      // loopback inbound a short, one-time settle window instead of recording a
      // startup race as a route timeout.
      if (waitForProxy) {
        await Future<void>.delayed(_routeProbeStartupDelay);
        if (!_canApplyRouteLatency(
          targetId,
          contextRevision,
          probeConfigurationRevision,
        )) {
          return;
        }
      }

      // With the optional parallel proxy disabled there is intentionally no
      // local Xray entry point in VPN mode. Do not fall back to Socket.connect:
      // that socket can be captured by the TUN and return a recursive 1–4 ms
      // pseudo-ping. The existing UI will correctly show `—`.
      if (_engineSnapshot.mode == ConnectionMode.vpnTun &&
          !_settings.localProxyInVpn) {
        _publishRouteLatency(
          targetId,
          const LatencyProbeResult.unavailable(),
          expectedContextRevision: contextRevision,
          expectedProbeConfigurationRevision: probeConfigurationRevision,
        );
        return;
      }

      final result = await _routeLatencyProbe.measure(
        httpPort: _settings.httpPort,
        probeUri: _settings.latencyProbeUri,
      );
      _publishRouteLatency(
        targetId,
        result,
        expectedContextRevision: contextRevision,
        expectedProbeConfigurationRevision: probeConfigurationRevision,
      );
    } finally {
      _routeLatencyRefreshCount--;
      if (!_closing) notifyListeners();
    }
  }

  Future<void> _refreshRouteLatencyForLifecycle({
    String? expectedTargetId,
    required bool waitForProxy,
  }) {
    final contextRevision = _latencyContextRevision;
    final probeConfigurationRevision = _routeProbeConfigurationRevision;
    final inFlight = _automaticRouteLatencyFuture;
    if (_automaticRouteLatencyContextRevision == contextRevision &&
        _automaticRouteLatencyProbeConfigurationRevision ==
            probeConfigurationRevision &&
        inFlight != null) {
      return inFlight;
    }
    final future = _refreshActiveRouteLatency(
      expectedTargetId: expectedTargetId,
      expectedContextRevision: contextRevision,
      expectedProbeConfigurationRevision: probeConfigurationRevision,
      waitForProxy: waitForProxy,
    );
    _automaticRouteLatencyContextRevision = contextRevision;
    _automaticRouteLatencyProbeConfigurationRevision =
        probeConfigurationRevision;
    _automaticRouteLatencyFuture = future;
    future.then<void>(
      (_) {
        if (identical(_automaticRouteLatencyFuture, future)) {
          _automaticRouteLatencyFuture = null;
        }
      },
      onError: (_, __) {
        if (identical(_automaticRouteLatencyFuture, future)) {
          _automaticRouteLatencyFuture = null;
        }
      },
    );
    return future;
  }

  void _publishRouteLatency(
    String targetId,
    LatencyProbeResult result, {
    required int expectedContextRevision,
    required int expectedProbeConfigurationRevision,
  }) {
    if (!_canApplyRouteLatency(
      targetId,
      expectedContextRevision,
      expectedProbeConfigurationRevision,
    )) {
      return;
    }
    _activeRouteLatencyTargetId = targetId;
    _activeRouteLatency = result;
    // Keep native foreground UI aligned with the value in the home screen.
    // Do not mutate the saved profile: its latency is the direct TCP metric
    // used in profile lists, whereas this is the current end-to-end route.
    final activeTarget =
        _profiles.targetById(targetId) ?? _engineSnapshot.profile;
    if (activeTarget != null) _publishRuntimeMetadata(activeTarget);
    notifyListeners();
  }

  Future<void> _refreshDirectTargetLatency(
    String targetId, {
    int? expectedContextRevision,
    bool requireSelectedTarget = false,
  }) async {
    final contextRevision = expectedContextRevision ?? _latencyContextRevision;
    final target = _profiles.targetById(targetId);
    if (target == null ||
        !_canApplyDirectLatency(
          contextRevision,
          targetId: requireSelectedTarget ? targetId : null,
        )) {
      return;
    }
    for (final profile in target.profiles) {
      await _profiles.refreshLatency(
        profile.id,
        shouldApply: () => _canApplyDirectLatency(
          contextRevision,
          targetId: requireSelectedTarget ? targetId : null,
        ),
      );
    }
  }

  void _schedulePendingVpnDirectLatency(String targetId) {
    if (_pendingVpnDirectLatencyTargetId != targetId ||
        _engineSnapshot.status != TunnelStatus.disconnected) {
      return;
    }
    _pendingVpnDirectLatencyTargetId = null;
    unawaited(
      _refreshDirectTargetLatency(
        targetId,
        expectedContextRevision: _latencyContextRevision,
        requireSelectedTarget: true,
      ),
    );
  }

  bool _isActiveRouteTarget(String targetId) =>
      _engineSnapshot.isConnected && _engineSnapshot.profile?.id == targetId;

  bool _canApplyRouteLatency(
    String targetId,
    int contextRevision,
    int probeConfigurationRevision,
  ) =>
      !_closing &&
      _latencyContextRevision == contextRevision &&
      _routeProbeConfigurationRevision == probeConfigurationRevision &&
      _engineSnapshot.isConnected &&
      _engineSnapshot.profile?.id == targetId;

  bool _canApplyDirectLatency(
    int contextRevision, {
    String? targetId,
  }) =>
      !_closing &&
      _latencyContextRevision == contextRevision &&
      !_engineSnapshot.isBusy &&
      _canRefreshSavedDirectLatencies &&
      (targetId == null || _profiles.selectedTarget?.id == targetId);

  bool get _canRefreshSavedDirectLatencies =>
      !_engineSnapshot.isConnected ||
      _engineSnapshot.mode != ConnectionMode.vpnTun ||
      _profiles.canMeasureLatencyWhileVpnActive;

  bool _latencyContextChanged(
    TunnelSnapshot previous,
    TunnelSnapshot next,
  ) =>
      previous.status != next.status ||
      previous.mode != next.mode ||
      previous.profile?.id != next.profile?.id;

  void _handleBecameConnected(TunnelSnapshot value) {
    // Clear a direct TCP value that can be left in Android's foreground
    // notification by an earlier connection. The route probe below will push
    // its own result once the active Xray path is ready.
    final activeTarget = value.profile == null
        ? null
        : _profiles.targetById(value.profile!.id) ?? value.profile;
    if (activeTarget != null) _publishRuntimeMetadata(activeTarget);
    final trigger = _hasConnectedBefore
        ? ExitLocationRefreshTrigger.reconnected
        : ExitLocationRefreshTrigger.connected;
    _hasConnectedBefore = true;
    unawaited(_requestEgressRefresh(trigger));
    unawaited(
      _refreshRouteLatencyForLifecycle(
        expectedTargetId: value.profile?.id,
        waitForProxy: true,
      ),
    );
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
      final response =
          await request.close().timeout(const Duration(seconds: 8));
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

  bool _canRefreshEgressTarget(
    String targetId,
    ExitLocationRefreshTrigger trigger,
  ) {
    return !_closing &&
        _engineSnapshot.isConnected &&
        _engineSnapshot.profile?.id == targetId &&
        !(_engineSnapshot.mode == ConnectionMode.vpnTun &&
            !_settings.localProxyInVpn);
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
        if (identity != null) {
          _egressIdentities[entry.key.toString()] = identity;
        }
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
      jsonEncode({
        for (final entry in _egressIdentities.entries)
          entry.key: entry.value.toJson()
      }),
    );
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
    _egressRefreshCoordinator.dispose();
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
    _egressRefreshCoordinator.dispose();
    _detachDependencies();
    await _cancelEngineSubscription();
    await _disposeEngine();
  }

  Future<void> _cancelEngineSubscription() =>
      _subscriptionCancelFuture ??= _engineSubscription.cancel();

  Future<void> _disposeEngine() => _disposeFuture ??= _engine.dispose();

  Future<void> setStatsUiActive(bool active) async {
    if (_closing || _engine is! TunnelStatsConsumerSink) return;
    await (_engine as TunnelStatsConsumerSink).setStatsUiActive(active);
  }

  void _syncFromEngine() {
    final next = _engine.current;
    final previous = _engineSnapshot;
    final becameConnected = next.isConnected && !previous.isConnected;
    if (_latencyContextChanged(previous, next)) {
      _latencyContextRevision++;
    }
    if (previous.isConnected &&
        previous.mode == ConnectionMode.vpnTun &&
        !next.isConnected) {
      _pendingVpnDirectLatencyTargetId = previous.profile?.id;
    }
    if (next.isConnected) _pendingVpnDirectLatencyTargetId = null;
    _engineSnapshot = next;
    _clearRouteLatencyIfStale();
    _adoptNativeRouteHealth(next);
    if (!next.isConnected && !next.isBusy) {
      _lastRuntimeMetadataKey = null;
    }
    if (becameConnected) {
      _handleBecameConnected(next);
    }
    if (_engineSnapshot.status == TunnelStatus.disconnected) {
      final targetId = _pendingVpnDirectLatencyTargetId;
      if (targetId != null) _schedulePendingVpnDirectLatency(targetId);
    }
    if (!_closing) notifyListeners();
  }

  void _clearRouteLatencyIfStale() {
    if (_engineSnapshot.isConnected &&
        _engineSnapshot.profile?.id == _activeRouteLatencyTargetId) {
      return;
    }
    _activeRouteLatency = null;
    _activeRouteLatencyTargetId = null;
  }

  void _adoptNativeRouteHealth(TunnelSnapshot snapshot) {
    if (!snapshot.isConnected) return;
    final targetId = snapshot.profile?.id;
    if (targetId == null || targetId.isEmpty) return;

    final PingStatus status = snapshot.effectivePingStatus;
    LatencyProbeResult? result;
    switch (status) {
      case PingStatus.success:
        final latencyMs = snapshot.effectiveLatencyMs;
        if (latencyMs != null && latencyMs > 0) {
          result = LatencyProbeResult.success(latencyMs);
        }
        break;
      case PingStatus.timeout:
        result = const LatencyProbeResult.timeout();
        break;
      case PingStatus.unavailable:
        result = const LatencyProbeResult.unavailable();
        break;
      case PingStatus.unknown:
        break;
    }
    if (result == null) return;

    _activeRouteLatencyTargetId = targetId;
    _activeRouteLatency = result;
  }

  void _detachDependencies() {
    if (_dependenciesDetached) return;
    _dependenciesDetached = true;
    _profiles.removeListener(_onProfilesChanged);
    _settings.removeListener(_onSettingsChanged);
  }

  void _onProfilesChanged() {
    if (_closing) return;
    final selectedTargetId = _profiles.selectedTarget?.id;
    if (_lastSelectedTargetId != selectedTargetId) {
      _lastSelectedTargetId = selectedTargetId;
      _latencyContextRevision++;
    }
    final active = _engineSnapshot.profile;
    if ((_engineSnapshot.isConnected || _engineSnapshot.isBusy) &&
        active != null &&
        _engine is TunnelRuntimeMetadataSink) {
      final refreshed = _profiles.targetById(active.id);
      if (refreshed != null) {
        if (_publishRuntimeMetadata(refreshed)) {
          if (_engineSnapshot.isConnected) {
            unawaited(
              _requestEgressRefresh(ExitLocationRefreshTrigger.profileChanged),
            );
          }
        }
      }
    }
    notifyListeners();
  }

  void _onSettingsChanged() {
    if (_closing) return;
    final configuredMode = _settings.mode;
    if (_lastConfiguredMode != configuredMode) {
      _lastConfiguredMode = configuredMode;
      _latencyContextRevision++;
    }
    final routeProbeUri = _settings.latencyProbeUri;
    if (_lastRouteProbeUri != routeProbeUri) {
      _lastRouteProbeUri = routeProbeUri;
      _routeProbeConfigurationRevision++;
      _activeRouteLatency = null;
      _activeRouteLatencyTargetId = null;
      if (_engineSnapshot.isConnected) {
        unawaited(
          _refreshRouteLatencyForLifecycle(
            expectedTargetId: _engineSnapshot.profile?.id,
            waitForProxy: false,
          ),
        );
      }
    }
    if (_engineSnapshot.isConnected && _engine is TunnelRuntimeSettingsSink) {
      unawaited(
        (_engine as TunnelRuntimeSettingsSink).updateRuntimeSettings(
          statsIntervalSeconds: _settings.statsIntervalSeconds,
          pingIntervalSeconds: _settings.pingIntervalSeconds,
          showNotificationSpeed: _settings.showNotificationSpeed,
          showNotificationPing: _settings.showNotificationPing,
        ),
      );
    }
    notifyListeners();
  }

  /// Synchronizes a native foreground presentation without ever replacing an
  /// active route result with the saved direct TCP result of the profile.
  ///
  /// Engines that do not expose an effective-latency bridge retain their
  /// existing metadata behaviour. Android implements the dedicated bridge so
  /// its foreground notification shows the same route ping as the home card.
  bool _publishRuntimeMetadata(TunnelTarget target) {
    if (!(_engineSnapshot.isConnected || _engineSnapshot.isBusy) ||
        _engine is! TunnelRuntimeMetadataSink) {
      return false;
    }

    final isActiveTarget = _engineSnapshot.profile?.id == target.id;
    final routeLatency =
        _isActiveRouteTarget(target.id) ? _activeRouteLatency : null;
    final usesEffectiveRoute =
        isActiveTarget && _engine is TunnelRuntimeEffectiveLatencySink;
    final metadataKey = _runtimeMetadataKey(
      target,
      effectiveRouteLatency: usesEffectiveRoute ? routeLatency : null,
      usesEffectiveRoute: usesEffectiveRoute,
    );
    if (metadataKey == _lastRuntimeMetadataKey) return false;
    _lastRuntimeMetadataKey = metadataKey;

    if (usesEffectiveRoute) {
      unawaited(
        (_engine as TunnelRuntimeEffectiveLatencySink).updateEffectiveLatency(
          target,
          latencyMs: routeLatency?.latencyMs,
          pingStatus: routeLatency?.status ?? PingStatus.unknown,
        ),
      );
    } else {
      unawaited(
        (_engine as TunnelRuntimeMetadataSink).updateTargetMetadata(target),
      );
    }
    return true;
  }

  String _runtimeMetadataKey(
    TunnelTarget target, {
    required bool usesEffectiveRoute,
    required LatencyProbeResult? effectiveRouteLatency,
  }) {
    final latencyKey = usesEffectiveRoute
        ? '${effectiveRouteLatency?.status.storageValue ?? 'unknown'}:'
            '${effectiveRouteLatency?.latencyMs ?? -1}'
        : 'direct:${target.latencyMs ?? -1}';
    return '${target.id}\u0000${target.name}\u0000$latencyKey';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    _egressRefreshCoordinator.dispose();
    _detachDependencies();
    _egressRevision.dispose();
    unawaited(_shutdownFuture ??= _disposeWithoutStopping());
    super.dispose();
  }
}
