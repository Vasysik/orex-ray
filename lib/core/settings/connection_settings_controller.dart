import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tunnel/tunnel_models.dart';

class ConnectionSettingsController extends ChangeNotifier {
  ConnectionSettingsController._({
    required SharedPreferences preferences,
    required Set<ConnectionMode> supportedModes,
    required ConnectionMode mode,
  })  : _preferences = preferences,
        _supportedModes = Set.unmodifiable(supportedModes),
        _mode = mode;

  static const _modeKey = 'orex_ray_connection_mode_v1';

  final SharedPreferences _preferences;
  final Set<ConnectionMode> _supportedModes;
  ConnectionMode _mode;

  static Future<ConnectionSettingsController> load({
    String? operatingSystem,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final platform = operatingSystem ?? Platform.operatingSystem;
    final supportedModes = supportedModesFor(platform);
    final stored = ConnectionMode.fromStorageValue(
      preferences.getString(_modeKey),
    );
    final fallback = defaultModeFor(platform);
    final mode = stored != null && supportedModes.contains(stored)
        ? stored
        : fallback;

    return ConnectionSettingsController._(
      preferences: preferences,
      supportedModes: supportedModes,
      mode: mode,
    );
  }

  ConnectionMode get mode => _mode;

  Set<ConnectionMode> get supportedModes => _supportedModes;

  bool supports(ConnectionMode mode) => _supportedModes.contains(mode);

  Future<void> setMode(ConnectionMode mode) async {
    if (!_supportedModes.contains(mode) || _mode == mode) return;
    _mode = mode;
    await _preferences.setString(_modeKey, mode.storageValue);
    notifyListeners();
  }

  static Set<ConnectionMode> supportedModesFor(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => const {
          ConnectionMode.systemProxy,
          ConnectionMode.vpnTun,
          ConnectionMode.localProxy,
        },
      'android' => const {
          ConnectionMode.vpnTun,
          ConnectionMode.localProxy,
        },
      _ => const {ConnectionMode.localProxy},
    };
  }

  static ConnectionMode defaultModeFor(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => ConnectionMode.systemProxy,
      'android' => ConnectionMode.vpnTun,
      _ => ConnectionMode.localProxy,
    };
  }
}
