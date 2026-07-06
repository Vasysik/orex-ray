import 'dart:async';

import 'package:flutter/foundation.dart';

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
      _engineSnapshot = value;
      notifyListeners();
    });
    _profiles.addListener(_onDependencyChanged);
    _settings.addListener(_onDependencyChanged);
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
      await _engine.stop();
      _syncFromEngine();
      return;
    }

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

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
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
        unawaited(
          (_engine as TunnelRuntimeMetadataSink).updateTargetMetadata(refreshed),
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    _detachDependencies();
    unawaited(_shutdownFuture ??= _disposeWithoutStopping());
    super.dispose();
  }
}
