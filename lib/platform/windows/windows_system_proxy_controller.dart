import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsProxyState {
  const WindowsProxyState({
    required this.enabled,
    required this.server,
    required this.bypass,
    required this.hasServer,
    required this.hasBypass,
  });

  final bool enabled;
  final String server;
  final String bypass;
  final bool hasServer;
  final bool hasBypass;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'server': server,
        'bypass': bypass,
        'hasServer': hasServer,
        'hasBypass': hasBypass,
      };

  factory WindowsProxyState.fromJson(Map<String, Object?> json) {
    return WindowsProxyState(
      enabled: json['enabled'] as bool? ?? false,
      server: json['server'] as String? ?? '',
      bypass: json['bypass'] as String? ?? '',
      hasServer: json['hasServer'] as bool? ?? false,
      hasBypass: json['hasBypass'] as bool? ?? false,
    );
  }
}

class WindowsSystemProxyController {
  WindowsSystemProxyController();

  static const _channel = MethodChannel('ru.orex.ray/system_proxy');
  static const _recoveryKey = 'orex_ray_windows_proxy_recovery_v1';

  Future<WindowsProxyState> read() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getState');
    if (raw == null) {
      throw StateError('Windows не вернул состояние системного прокси.');
    }
    return WindowsProxyState(
      enabled: raw['enabled'] as bool? ?? false,
      server: raw['server'] as String? ?? '',
      bypass: raw['bypass'] as String? ?? '',
      hasServer: raw['hasServer'] as bool? ?? false,
      hasBypass: raw['hasBypass'] as bool? ?? false,
    );
  }

  Future<void> recoverIfNeeded() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_recoveryKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final state = WindowsProxyState.fromJson(
        Map<String, Object?>.from(decoded),
      );
      await restore(state);
    } finally {
      await preferences.remove(_recoveryKey);
    }
  }

  Future<WindowsProxyState> enable({
    required String server,
    required String bypass,
  }) async {
    final previous = await read();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_recoveryKey, jsonEncode(previous.toJson()));

    try {
      await _channel.invokeMethod<void>('setProxy', {
        'server': server,
        'bypass': bypass,
      });
      return previous;
    } catch (_) {
      await preferences.remove(_recoveryKey);
      rethrow;
    }
  }

  Future<void> restore(WindowsProxyState state) async {
    await _channel.invokeMethod<void>('restore', state.toJson());
  }

  Future<void> restoreSaved() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_recoveryKey);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      await restore(
        WindowsProxyState.fromJson(Map<String, Object?>.from(decoded)),
      );
    }
    await preferences.remove(_recoveryKey);
  }

  Future<void> clearRecoveryMarker() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_recoveryKey);
  }
}
