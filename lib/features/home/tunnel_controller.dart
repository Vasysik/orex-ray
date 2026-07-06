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

  Future<void> setMode(ConnectionMode mode) async {
    if (!canChangeMode || !supportedModes.contains(mode)) return;
    await _settings.setMode(mode);
  }

  Future<void> toggle() async {
    final current = snapshot;
    if (current.isBusy) return;
    if (current.isConnected) {
      await _engine.stop();
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
  }

  void _onDependencyChanged() => notifyListeners();

  @override
  void dispose() {
    _profiles.removeListener(_onDependencyChanged);
    _settings.removeListener(_onDependencyChanged);
    unawaited(_engineSubscription.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
