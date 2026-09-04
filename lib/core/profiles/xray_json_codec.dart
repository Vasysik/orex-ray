import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../tunnel/tunnel_models.dart';
import '../xray/xray_config_builder.dart';

class XrayJsonDecodeResult {
  const XrayJsonDecodeResult({
    required this.profiles,
    required this.skippedUnsupported,
  });

  final List<TunnelProfile> profiles;
  final int skippedUnsupported;
}

/// Converts regular Xray JSON configs to OrexRay profiles and back.
///
/// Supported input roots:
/// * one complete Xray config (`{ "outbounds": [...] }`);
/// * one outbound object (`{ "protocol": "vless", ... }`);
/// * arrays containing either form, recursively.
///
/// Both the compact settings used by current Xray builds and the traditional
/// `vnext`/`servers` settings are accepted for the protocols represented by
/// [OutboundProtocol]. Unsupported system outbounds (freedom, blackhole, DNS,
/// etc.) are ignored rather than turning an otherwise useful config invalid.
class XrayJsonCodec {
  const XrayJsonCodec();

  static const maxPayloadBytes = 5 * 1024 * 1024;
  static const maxProfiles = 500;
  static const _maxNestingDepth = 32;

  XrayJsonDecodeResult decode(
    String payload, {
    String sourceLabel = '',
  }) {
    if (utf8.encode(payload).length > maxPayloadBytes) {
      throw const FormatException('JSON Xray больше 5 МБ');
    }
    var text = payload.trim();
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1).trimLeft();
    }
    if (text.isEmpty) {
      throw const FormatException('JSON Xray пуст');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Некорректный JSON Xray');
    }

    final profiles = <TunnelProfile>[];
    var skippedUnsupported = 0;

    void addRoot(
      Object? value, {
      String? nameHint,
      int depth = 0,
    }) {
      if (depth > _maxNestingDepth) {
        throw const FormatException('Слишком глубокая вложенность JSON Xray');
      }
      if (profiles.length > maxProfiles) {
        throw const FormatException('В JSON больше 500 профилей');
      }
      if (value is List) {
        for (final item in value) {
          addRoot(item, depth: depth + 1);
        }
        return;
      }
      if (value is! Map) {
        throw const FormatException(
          'JSON Xray должен быть объектом или массивом объектов',
        );
      }

      final map = Map<String, Object?>.from(value);
      final rootName = _rootName(map) ?? nameHint;
      final outbounds = map['outbounds'];
      if (outbounds is List) {
        final outboundMaps = outbounds
            .whereType<Map>()
            .map((item) => Map<String, Object?>.from(item))
            .toList(growable: false);
        final supportedCount = outboundMaps.where((item) {
          final protocol = _string(item['protocol']);
          return OutboundProtocol.fromStorageValue(protocol) != null;
        }).length;

        for (final item in outboundMaps) {
          final parsed = _parseOutbound(
            item,
            sourceLabel: sourceLabel,
            // In a regular Xray config `direct`/`block` outbounds make the
            // raw list longer than one. The config-level name still belongs
            // to the single usable proxy outbound.
            nameHint: supportedCount == 1 ? rootName : null,
          );
          if (parsed == null) {
            final protocol = _string(item['protocol']).toLowerCase();
            if (!_isIgnorableProtocol(protocol)) skippedUnsupported += 1;
          } else {
            if (profiles.length + parsed.length > maxProfiles) {
              throw const FormatException('В JSON больше 500 профилей');
            }
            profiles.addAll(parsed);
          }
        }
        return;
      }

      if (map['protocol'] is String) {
        final parsed = _parseOutbound(
          map,
          sourceLabel: sourceLabel,
          nameHint: rootName,
        );
        if (parsed == null) {
          final protocol = _string(map['protocol']).toLowerCase();
          if (!_isIgnorableProtocol(protocol)) skippedUnsupported += 1;
        } else {
          if (profiles.length + parsed.length > maxProfiles) {
            throw const FormatException('В JSON больше 500 профилей');
          }
          profiles.addAll(parsed);
        }
        return;
      }

      throw const FormatException(
        'Не найден объект outbound или массив outbounds',
      );
    }

    addRoot(decoded);
    if (profiles.length > maxProfiles) {
      throw const FormatException('В JSON больше 500 профилей');
    }
    if (profiles.isEmpty) {
      throw const FormatException(
        'В JSON нет поддерживаемых Xray outbound-профилей',
      );
    }
    return XrayJsonDecodeResult(
      profiles: List.unmodifiable(profiles),
      skippedUnsupported: skippedUnsupported,
    );
  }

  /// Exports one profile as a complete runnable Xray config. Multiple profiles
  /// are exported as an array of complete configs so the result can be fed back
  /// to [decode] without losing profile boundaries.
  String encodeProfiles(
    Iterable<TunnelProfile> values, {
    bool forceArray = false,
  }) {
    final profiles = values.toList(growable: false);
    if (profiles.isEmpty) {
      throw const FormatException('Нет профилей для экспорта');
    }
    if (profiles.length > maxProfiles) {
      throw const FormatException('Можно экспортировать не больше 500 профилей');
    }

    final configs = profiles.map(_exportConfig).toList(growable: false);
    final value = !forceArray && configs.length == 1 ? configs.single : configs;
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    if (utf8.encode(encoded).length > maxPayloadBytes) {
      throw const FormatException('Экспорт JSON Xray больше 5 МБ');
    }
    return encoded;
  }

  Map<String, Object?> _exportConfig(TunnelProfile profile) {
    final raw = const XrayConfigBuilder().buildLocalProxy(
      TunnelTarget.single(profile),
      enableInboundStats: false,
    );
    final config = Map<String, Object?>.from(jsonDecode(raw) as Map);
    // Keep a readable tag for normal profile names. `direct` and `block` are
    // already used by the generated system outbounds, so encode only those
    // reserved names into a reversible tag instead of creating duplicate tags.
    final exportTag = _exportTag(profile.name);
    final outbounds = (config['outbounds'] as List?)?.whereType<Map>().toList();
    if (outbounds != null) {
      for (final rawOutbound in outbounds) {
        if (rawOutbound['tag'] == 'proxy') {
          rawOutbound['tag'] = exportTag;
          break;
        }
      }
    }
    final routing = config['routing'];
    if (routing is Map) {
      final rules = routing['rules'];
      if (rules is List) {
        for (final rule in rules.whereType<Map>()) {
          if (rule['outboundTag'] == 'proxy') {
            rule['outboundTag'] = exportTag;
          }
        }
      }
    }
    return config;
  }

  List<TunnelProfile>? _parseOutbound(
    Map<String, Object?> outbound, {
    required String sourceLabel,
    String? nameHint,
  }) {
    final protocolRaw = _string(outbound['protocol']);
    final protocol = OutboundProtocol.fromStorageValue(protocolRaw);
    if (protocol == null) return null;

    final settings = _map(outbound['settings']);
    final stream = _parseStreamSettings(_map(outbound['streamSettings']));
    final outboundTag = _string(outbound['tag']);
    final hintedName = nameHint?.trim();
    final tagName = _displayNameFromTag(outboundTag);
    final defaultName = hintedName != null && hintedName.isNotEmpty
        ? hintedName
        : tagName;

    final endpoints = <_Endpoint>[];
    final vnext = settings['vnext'];
    final servers = settings['servers'];

    if ((protocol == OutboundProtocol.vless ||
            protocol == OutboundProtocol.vmess) &&
        vnext is List) {
      for (final item in vnext.whereType<Map>()) {
        final server = Map<String, Object?>.from(item);
        final address = _string(server['address']);
        final port = _port(server['port']);
        final users = server['users'];
        if (users is List && users.whereType<Map>().isNotEmpty) {
          for (final rawUser in users.whereType<Map>()) {
            final user = Map<String, Object?>.from(rawUser);
            endpoints.add(
              _Endpoint(
                address: address,
                port: port,
                userId: _string(user['id']),
                encryption: protocol == OutboundProtocol.vless
                    ? _string(user['encryption'], fallback: 'none')
                    : 'none',
                vmessSecurity: protocol == OutboundProtocol.vmess
                    ? _string(user['security'], fallback: 'auto')
                    : 'auto',
                flow: _string(user['flow']),
              ),
            );
          }
        } else {
          endpoints.add(_Endpoint(address: address, port: port));
        }
      }
    } else if (servers is List) {
      for (final item in servers.whereType<Map>()) {
        final server = Map<String, Object?>.from(item);
        if (protocol == OutboundProtocol.socks ||
            protocol == OutboundProtocol.http) {
          final users = server['users'];
          if (users is List && users.whereType<Map>().isNotEmpty) {
            for (final rawUser in users.whereType<Map>()) {
              final user = Map<String, Object?>.from(rawUser);
              endpoints.add(
                _Endpoint(
                  address: _string(server['address']),
                  port: _port(server['port']),
                  userId: _string(user['user'], fallback: _string(user['email'])),
                  password: _string(user['pass'], fallback: _string(user['password'])),
                ),
              );
            }
            continue;
          }
        }
        endpoints.add(
          _Endpoint(
            address: _string(server['address']),
            port: _port(server['port']),
            password: _string(
              server['password'],
              fallback: _string(server['pass']),
            ),
            encryption: protocol == OutboundProtocol.shadowsocks
                ? _string(server['method'], fallback: 'none')
                : 'none',
            userId: _string(server['user']),
          ),
        );
      }
    } else {
      endpoints.add(
        _Endpoint(
          address: _string(settings['address']),
          port: _port(settings['port']),
          userId: _string(
            settings['id'],
            fallback: _string(settings['user']),
          ),
          password: _string(
            settings['password'],
            fallback: _string(settings['pass']),
          ),
          encryption: protocol == OutboundProtocol.shadowsocks
              ? _string(settings['method'], fallback: 'none')
              : _string(settings['encryption'], fallback: 'none'),
          vmessSecurity: _string(settings['security'], fallback: 'auto'),
          flow: _string(settings['flow']),
        ),
      );
    }

    if (endpoints.isEmpty) {
      throw FormatException('Outbound ${protocol.title} не содержит серверов');
    }
    if (endpoints.length > maxProfiles) {
      throw const FormatException('В одном outbound больше 500 профилей');
    }

    final profiles = <TunnelProfile>[];
    for (var index = 0; index < endpoints.length; index++) {
      final endpoint = endpoints[index];
      _validateEndpoint(protocol, endpoint);
      final name = (defaultName?.trim().isNotEmpty ?? false)
          ? endpoints.length == 1
              ? defaultName!.trim()
              : '${defaultName!.trim()} ${index + 1}'
          : endpoint.address;
      profiles.add(
        _profile(
          protocol: protocol,
          name: name,
          endpoint: endpoint,
          stream: stream,
          sourceLabel: sourceLabel,
        ),
      );
    }
    return profiles;
  }

  TunnelProfile _profile({
    required OutboundProtocol protocol,
    required String name,
    required _Endpoint endpoint,
    required _StreamSettings stream,
    required String sourceLabel,
  }) {
    final vmessSecurity = protocol == OutboundProtocol.vmess
        ? endpoint.vmessSecurity
        : 'auto';
    final encryption = switch (protocol) {
      OutboundProtocol.vless => endpoint.encryption.isEmpty
          ? 'none'
          : endpoint.encryption,
      OutboundProtocol.shadowsocks => endpoint.encryption,
      _ => 'none',
    };
    final canonical = jsonEncode(<String, Object?>{
      'protocol': protocol.storageValue,
      'address': endpoint.address.toLowerCase(),
      'port': endpoint.port,
      'userId': endpoint.userId,
      'password': endpoint.password,
      'vmessSecurity': vmessSecurity,
      'encryption': encryption,
      'flow': endpoint.flow,
      'security': stream.security,
      'transport': stream.transport,
      'serverName': stream.serverName.toLowerCase(),
      'fingerprint': stream.fingerprint,
      'realityPassword': stream.realityPassword,
      'shortId': stream.shortId,
      'spiderX': stream.spiderX,
      'path': stream.path,
      'host': stream.host.toLowerCase(),
      'serviceName': stream.serviceName,
      'grpcMode': stream.grpcMode,
      'alpn': [...stream.alpn]..sort(),
      'allowInsecure': stream.allowInsecure,
    });
    final id = sha256.convert(utf8.encode(canonical)).toString().substring(0, 32);
    return TunnelProfile(
      id: id,
      name: name,
      address: endpoint.address,
      port: endpoint.port,
      userId: endpoint.userId,
      password: endpoint.password,
      outboundProtocol: protocol,
      vmessSecurity: vmessSecurity,
      encryption: encryption,
      flow: endpoint.flow,
      security: stream.security,
      transport: stream.transport,
      serverName: stream.serverName,
      fingerprint: stream.fingerprint,
      realityPassword: stream.realityPassword,
      shortId: stream.shortId,
      spiderX: stream.spiderX,
      path: stream.path,
      host: stream.host,
      serviceName: stream.serviceName,
      grpcMode: stream.grpcMode,
      alpn: stream.alpn,
      allowInsecure: stream.allowInsecure,
      sourceLink: sourceLabel,
    );
  }

  _StreamSettings _parseStreamSettings(Map<String, Object?> settings) {
    if (settings.isEmpty) return const _StreamSettings();
    final transport = _normalizeTransport(
      _string(settings['network'], fallback: 'raw'),
    );
    final security = _string(settings['security'], fallback: 'none')
        .trim()
        .toLowerCase();
    if (!{'none', 'tls', 'reality'}.contains(security)) {
      throw FormatException('Неподдерживаемый Xray security=$security');
    }

    var path = '';
    var host = '';
    var serviceName = '';
    var grpcMode = '';
    if (transport == 'raw') {
      final raw = _map(settings['rawSettings']).isNotEmpty
          ? _map(settings['rawSettings'])
          : _map(settings['tcpSettings']);
      final header = _map(raw['header']);
      final headerType = _string(header['type'], fallback: 'none').toLowerCase();
      if (headerType != 'none' && headerType.isNotEmpty) {
        throw FormatException(
          'TCP header type=$headerType пока нельзя представить профилем OrexRay',
        );
      }
    } else if (transport == 'websocket') {
      final ws = _map(settings['wsSettings']);
      path = _string(ws['path']);
      host = _string(ws['host']);
      if (host.isEmpty) {
        final headers = _map(ws['headers']);
        host = _string(headers['Host'], fallback: _string(headers['host']));
      }
    } else if (transport == 'grpc') {
      final grpc = _map(settings['grpcSettings']);
      serviceName = _string(grpc['serviceName']);
      grpcMode = grpc['multiMode'] == true ? 'multi' : _string(grpc['mode']);
    } else if (transport == 'xhttp') {
      final xhttp = _map(settings['xhttpSettings']).isNotEmpty
          ? _map(settings['xhttpSettings'])
          : _map(settings['splithttpSettings']);
      path = _string(xhttp['path']);
      host = _string(xhttp['host']);
    } else if (transport == 'httpupgrade') {
      final upgrade = _map(settings['httpupgradeSettings']);
      path = _string(upgrade['path']);
      host = _string(upgrade['host']);
    }

    var serverName = '';
    var fingerprint = 'chrome';
    var realityPassword = '';
    var shortId = '';
    var spiderX = '';
    var alpn = const <String>[];
    var allowInsecure = false;
    if (security == 'reality') {
      final reality = _map(settings['realitySettings']);
      serverName = _string(reality['serverName']);
      fingerprint = _string(reality['fingerprint'], fallback: 'chrome');
      realityPassword = _string(
        reality['password'],
        fallback: _string(reality['publicKey']),
      );
      shortId = _string(reality['shortId']);
      spiderX = _string(reality['spiderX']);
      if (realityPassword.trim().isEmpty) {
        throw const FormatException('Для REALITY в JSON нужен public key');
      }
    } else if (security == 'tls') {
      final tls = _map(settings['tlsSettings']);
      serverName = _string(tls['serverName']);
      fingerprint = _string(tls['fingerprint'], fallback: 'chrome');
      alpn = _stringList(tls['alpn']);
      allowInsecure = tls['allowInsecure'] == true;
    }

    return _StreamSettings(
      security: security,
      transport: transport,
      serverName: serverName,
      fingerprint: fingerprint,
      realityPassword: realityPassword,
      shortId: shortId,
      spiderX: spiderX,
      path: path,
      host: host,
      serviceName: serviceName,
      grpcMode: grpcMode,
      alpn: alpn,
      allowInsecure: allowInsecure,
    );
  }

  void _validateEndpoint(OutboundProtocol protocol, _Endpoint endpoint) {
    if (endpoint.address.trim().isEmpty) {
      throw FormatException('В outbound ${protocol.title} нет адреса');
    }
    if (endpoint.address.length > 1024) {
      throw const FormatException('Адрес Xray слишком длинный');
    }
    if (endpoint.port < 1 || endpoint.port > 65535) {
      throw const FormatException('Некорректный порт Xray outbound');
    }
    if ((protocol == OutboundProtocol.vless ||
            protocol == OutboundProtocol.vmess) &&
        endpoint.userId.trim().isEmpty) {
      throw FormatException('В outbound ${protocol.title} нет UUID');
    }
    if ((protocol == OutboundProtocol.trojan ||
            protocol == OutboundProtocol.shadowsocks) &&
        endpoint.password.isEmpty) {
      throw FormatException('В outbound ${protocol.title} нет пароля');
    }
    if (protocol == OutboundProtocol.shadowsocks &&
        endpoint.encryption.trim().isEmpty) {
      throw const FormatException('В Shadowsocks outbound нет метода');
    }
    if ((protocol == OutboundProtocol.socks ||
            protocol == OutboundProtocol.http) &&
        (endpoint.userId.isEmpty != endpoint.password.isEmpty)) {
      throw const FormatException(
        'Для SOCKS/HTTP нужны и имя пользователя, и пароль',
      );
    }
  }

  String _normalizeTransport(String value) => switch (value.trim().toLowerCase()) {
        '' || 'tcp' || 'raw' => 'raw',
        'ws' || 'websocket' => 'websocket',
        'grpc' => 'grpc',
        'xhttp' || 'splithttp' => 'xhttp',
        'httpupgrade' => 'httpupgrade',
        final unsupported => throw FormatException(
            'Неподдерживаемый Xray transport=$unsupported',
          ),
      };

  int _port(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  Map<String, Object?> _map(Object? value) => value is Map
      ? Map<String, Object?>.from(value)
      : const <String, Object?>{};

  String _string(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.trim();
    if (value is num || value is bool) return '$value';
    return fallback;
  }

  List<String> _stringList(Object? value) {
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(16)
          .toList(growable: false);
    }
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(16)
          .toList(growable: false);
    }
    return const [];
  }

  String? _rootName(Map<String, Object?> value) {
    for (final key in const ['remarks', 'remark', 'name', 'ps']) {
      final name = _string(value[key]);
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  bool _isIgnorableProtocol(String protocol) => const {
        'freedom',
        'blackhole',
        'dns',
        'loopback',
      }.contains(protocol);

  static const _encodedNamePrefix = 'orexray-name-b64:';

  String _exportTag(String profileName) {
    final name = profileName.trim();
    // Xray runtime tags such as `proxy`, `proxy-*`, `direct` and `block` do
    // not carry a useful user-facing name when imported. Encode only those
    // names (plus our own marker prefix) so normal tags stay readable.
    if (_usefulTag(name) && !name.startsWith(_encodedNamePrefix)) return name;
    final encoded = base64Url.encode(utf8.encode(name)).replaceAll('=', '');
    return '$_encodedNamePrefix$encoded';
  }

  String? _displayNameFromTag(String tag) {
    const prefix = _encodedNamePrefix;
    if (tag.startsWith(prefix)) {
      final encoded = tag.substring(prefix.length);
      if (encoded.isNotEmpty) {
        final padding = (4 - encoded.length % 4) % 4;
        final padded = encoded.padRight(encoded.length + padding, '=');
        try {
          final decoded = utf8.decode(base64Url.decode(padded)).trim();
          if (decoded.isNotEmpty) return decoded;
        } on FormatException {
          // Fall through and treat an invalid marker as a regular tag.
        }
      }
    }
    return _usefulTag(tag) ? tag : null;
  }

  bool _usefulTag(String tag) {
    final normalized = tag.toLowerCase();
    return tag.isNotEmpty &&
        normalized != 'proxy' &&
        normalized != 'direct' &&
        normalized != 'block' &&
        !normalized.startsWith('proxy-');
  }
}

class _Endpoint {
  const _Endpoint({
    required this.address,
    required this.port,
    this.userId = '',
    this.password = '',
    this.vmessSecurity = 'auto',
    this.encryption = 'none',
    this.flow = '',
  });

  final String address;
  final int port;
  final String userId;
  final String password;
  final String vmessSecurity;
  final String encryption;
  final String flow;
}

class _StreamSettings {
  const _StreamSettings({
    this.security = 'none',
    this.transport = 'raw',
    this.serverName = '',
    this.fingerprint = 'chrome',
    this.realityPassword = '',
    this.shortId = '',
    this.spiderX = '',
    this.path = '',
    this.host = '',
    this.serviceName = '',
    this.grpcMode = '',
    this.alpn = const [],
    this.allowInsecure = false,
  });

  final String security;
  final String transport;
  final String serverName;
  final String fingerprint;
  final String realityPassword;
  final String shortId;
  final String spiderX;
  final String path;
  final String host;
  final String serviceName;
  final String grpcMode;
  final List<String> alpn;
  final bool allowInsecure;
}
