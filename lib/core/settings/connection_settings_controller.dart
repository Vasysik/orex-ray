import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tunnel/tunnel_models.dart';

enum DnsPreset {
  automatic,
  cloudflare,
  google,
  custom;

  String get storageValue => name;

  String get title => switch (this) {
        DnsPreset.automatic => 'Автоматически',
        DnsPreset.cloudflare => 'Cloudflare',
        DnsPreset.google => 'Google',
        DnsPreset.custom => 'Свой DNS',
      };

  String get description => switch (this) {
        DnsPreset.automatic => '1.1.1.1 и 8.8.8.8',
        DnsPreset.cloudflare => '1.1.1.1 и 1.0.0.1',
        DnsPreset.google => '8.8.8.8 и 8.8.4.4',
        DnsPreset.custom => 'Адреса, заданные вручную',
      };

  static DnsPreset fromStorageValue(String? value) => switch (value) {
        'cloudflare' => DnsPreset.cloudflare,
        'google' => DnsPreset.google,
        'custom' => DnsPreset.custom,
        _ => DnsPreset.automatic,
      };
}

class ConnectionSettingsController extends ChangeNotifier {
  ConnectionSettingsController._({
    required SharedPreferences preferences,
    required Set<ConnectionMode> supportedModes,
    required ConnectionMode mode,
    required int socksPort,
    required int httpPort,
    required int mtu,
    required bool allowLan,
    required bool bypassPrivateNetworks,
    required bool sniffingEnabled,
    required String logLevel,
    required DnsPreset dnsPreset,
    required String customDns,
  })  : _preferences = preferences,
        _supportedModes = Set.unmodifiable(supportedModes),
        _mode = mode,
        _socksPort = socksPort,
        _httpPort = httpPort,
        _mtu = mtu,
        _allowLan = allowLan,
        _bypassPrivateNetworks = bypassPrivateNetworks,
        _sniffingEnabled = sniffingEnabled,
        _logLevel = logLevel,
        _dnsPreset = dnsPreset,
        _customDns = customDns;

  static const _modeKey = 'orex_ray_connection_mode_v1';
  static const _socksPortKey = 'orex_ray_socks_port_v1';
  static const _httpPortKey = 'orex_ray_http_port_v1';
  static const _mtuKey = 'orex_ray_mtu_v1';
  static const _allowLanKey = 'orex_ray_allow_lan_v1';
  static const _bypassPrivateKey = 'orex_ray_bypass_private_v1';
  static const _sniffingKey = 'orex_ray_sniffing_v1';
  static const _logLevelKey = 'orex_ray_log_level_v1';
  static const _dnsPresetKey = 'orex_ray_dns_preset_v1';
  static const _customDnsKey = 'orex_ray_custom_dns_v1';

  static const int defaultSocksPort = 20808;
  static const int defaultHttpPort = 20809;
  static const int defaultMtu = 1500;

  final SharedPreferences _preferences;
  final Set<ConnectionMode> _supportedModes;

  ConnectionMode _mode;
  int _socksPort;
  int _httpPort;
  int _mtu;
  bool _allowLan;
  bool _bypassPrivateNetworks;
  bool _sniffingEnabled;
  String _logLevel;
  DnsPreset _dnsPreset;
  String _customDns;

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
      socksPort: _validPort(preferences.getInt(_socksPortKey)) ?? defaultSocksPort,
      httpPort: _validPort(preferences.getInt(_httpPortKey)) ?? defaultHttpPort,
      mtu: _validMtu(preferences.getInt(_mtuKey)) ?? defaultMtu,
      allowLan: preferences.getBool(_allowLanKey) ?? false,
      bypassPrivateNetworks:
          preferences.getBool(_bypassPrivateKey) ?? true,
      sniffingEnabled: preferences.getBool(_sniffingKey) ?? true,
      logLevel: _normalizeLogLevel(preferences.getString(_logLevelKey)),
      dnsPreset: DnsPreset.fromStorageValue(
        preferences.getString(_dnsPresetKey),
      ),
      customDns: preferences.getString(_customDnsKey)?.trim() ?? '',
    );
  }

  ConnectionMode get mode => _mode;
  Set<ConnectionMode> get supportedModes => _supportedModes;
  int get socksPort => _socksPort;
  int get httpPort => _httpPort;
  int get mtu => _mtu;
  bool get allowLan => _allowLan;
  bool get bypassPrivateNetworks => _bypassPrivateNetworks;
  bool get sniffingEnabled => _sniffingEnabled;
  String get logLevel => _logLevel;
  DnsPreset get dnsPreset => _dnsPreset;
  String get customDns => _customDns;

  List<String> get dnsServers {
    return switch (_dnsPreset) {
      DnsPreset.automatic => const ['1.1.1.1', '8.8.8.8'],
      DnsPreset.cloudflare => const ['1.1.1.1', '1.0.0.1'],
      DnsPreset.google => const ['8.8.8.8', '8.8.4.4'],
      DnsPreset.custom => _parseDnsList(_customDns),
    };
  }

  bool supports(ConnectionMode mode) => _supportedModes.contains(mode);

  Future<void> setMode(ConnectionMode mode) async {
    if (!_supportedModes.contains(mode) || _mode == mode) return;
    _mode = mode;
    await _preferences.setString(_modeKey, mode.storageValue);
    notifyListeners();
  }

  Future<void> setSocksPort(int value) async {
    final port = _validPort(value);
    if (port == null) throw const FormatException('Порт должен быть от 1 до 65535');
    if (port == _httpPort) throw const FormatException('SOCKS и HTTP должны использовать разные порты');
    if (_socksPort == port) return;
    _socksPort = port;
    await _preferences.setInt(_socksPortKey, port);
    notifyListeners();
  }

  Future<void> setHttpPort(int value) async {
    final port = _validPort(value);
    if (port == null) throw const FormatException('Порт должен быть от 1 до 65535');
    if (port == _socksPort) throw const FormatException('SOCKS и HTTP должны использовать разные порты');
    if (_httpPort == port) return;
    _httpPort = port;
    await _preferences.setInt(_httpPortKey, port);
    notifyListeners();
  }

  Future<void> setMtu(int value) async {
    final mtu = _validMtu(value);
    if (mtu == null) throw const FormatException('MTU должен быть от 1280 до 9000');
    if (_mtu == mtu) return;
    _mtu = mtu;
    await _preferences.setInt(_mtuKey, mtu);
    notifyListeners();
  }

  Future<void> setAllowLan(bool value) async {
    if (_allowLan == value) return;
    _allowLan = value;
    await _preferences.setBool(_allowLanKey, value);
    notifyListeners();
  }

  Future<void> setBypassPrivateNetworks(bool value) async {
    if (_bypassPrivateNetworks == value) return;
    _bypassPrivateNetworks = value;
    await _preferences.setBool(_bypassPrivateKey, value);
    notifyListeners();
  }

  Future<void> setSniffingEnabled(bool value) async {
    if (_sniffingEnabled == value) return;
    _sniffingEnabled = value;
    await _preferences.setBool(_sniffingKey, value);
    notifyListeners();
  }

  Future<void> setLogLevel(String value) async {
    final normalized = _normalizeLogLevel(value);
    if (_logLevel == normalized) return;
    _logLevel = normalized;
    await _preferences.setString(_logLevelKey, normalized);
    notifyListeners();
  }

  Future<void> setDnsPreset(DnsPreset value) async {
    if (_dnsPreset == value) return;
    _dnsPreset = value;
    await _preferences.setString(_dnsPresetKey, value.storageValue);
    notifyListeners();
  }

  Future<void> setCustomDns(String value) async {
    final normalized = value.trim();
    final parsed = _parseDnsList(normalized);
    if (normalized.isNotEmpty && parsed.isEmpty) {
      throw const FormatException('Укажи хотя бы один корректный DNS-адрес');
    }
    if (_customDns == normalized) return;
    _customDns = normalized;
    await _preferences.setString(_customDnsKey, normalized);
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

  static int? _validPort(int? value) =>
      value != null && value >= 1 && value <= 65535 ? value : null;

  static int? _validMtu(int? value) =>
      value != null && value >= 1280 && value <= 9000 ? value : null;

  static String _normalizeLogLevel(String? value) => switch (value) {
        'warning' => 'warning',
        'info' => 'info',
        'debug' => 'debug',
        _ => 'error',
      };

  static List<String> _parseDnsList(String value) {
    final seen = <String>{};
    for (final part in value.split(RegExp(r'[\s,;]+'))) {
      final item = part.trim();
      if (item.isEmpty) continue;
      if (_looksLikeHostOrIp(item)) seen.add(item);
    }
    return seen.toList(growable: false);
  }

  static bool _looksLikeHostOrIp(String value) {
    if (value.length > 253 || value.contains(' ')) return false;
    return RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
  }
}
