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

  bool sameAs(WindowsProxyState other) {
    return enabled == other.enabled &&
        server == other.server &&
        bypass == other.bypass &&
        hasServer == other.hasServer &&
        hasBypass == other.hasBypass;
  }
}

class WindowsSystemProxyController {
  WindowsSystemProxyController();

  static const _channel = MethodChannel('ru.orex.ray/system_proxy');
  static const _recoveryKey = 'orex_ray_windows_proxy_recovery_v1';
  static const _ownedKey = 'orex_ray_windows_proxy_owned_v1';

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

  Future<void> recoverIfNeeded() => restoreSaved();

  Future<WindowsProxyState> enable({
    required String server,
    required String bypass,
  }) async {
    final previous = await read();
    final owned = WindowsProxyState(
      enabled: true,
      server: server,
      bypass: bypass,
      hasServer: true,
      hasBypass: true,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_recoveryKey, jsonEncode(previous.toJson()));
    await preferences.setString(_ownedKey, jsonEncode(owned.toJson()));

    try {
      await _channel.invokeMethod<void>('setProxy', {
        'server': server,
        'bypass': bypass,
      });
      return previous;
    } catch (_) {
      try {
        await restore(previous);
        await preferences.remove(_recoveryKey);
        await preferences.remove(_ownedKey);
      } catch (_) {
        // Keep the recovery marker so the next launch can retry restoration.
      }
      rethrow;
    }
  }

  Future<void> restore(WindowsProxyState state) async {
    await _channel.invokeMethod<void>('restore', state.toJson());
  }

  Future<void> restoreSaved() async {
    final preferences = await SharedPreferences.getInstance();
    final recoveryRaw = preferences.getString(_recoveryKey);
    if (recoveryRaw == null || recoveryRaw.isEmpty) {
      await preferences.remove(_ownedKey);
      return;
    }

    try {
      final previous = _decodeState(recoveryRaw);
      if (previous == null) return;

      final ownedRaw = preferences.getString(_ownedKey);
      final owned = ownedRaw == null ? null : _decodeState(ownedRaw);

      // Old versions did not store an ownership marker. Preserve one-time
      // crash recovery for those installs, but new state is restored only
      // while Windows still contains exactly the proxy OrexRay installed.
      if (owned == null || (await read()).sameAs(owned)) {
        await restore(previous);
      }
    } finally {
      await preferences.remove(_recoveryKey);
      await preferences.remove(_ownedKey);
    }
  }

  Future<void> clearRecoveryMarker() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_recoveryKey);
    await preferences.remove(_ownedKey);
  }

  WindowsProxyState? _decodeState(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return WindowsProxyState.fromJson(Map<String, Object?>.from(decoded));
  }
}
