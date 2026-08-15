import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../tunnel/tunnel_models.dart';
import 'vless_link_parser.dart';

/// Imports the URI formats that can be represented by the Xray configuration
/// builder. VLESS remains parsed by [VlessLinkParser] so its canonical ID and
/// legacy validation behaviour stay byte-for-byte compatible.
class ProxyLinkParser {
  const ProxyLinkParser();

  static const _maxLinkLength = 64 * 1024;
  static const _maxNameLength = 256;
  static const _maxAddressLength = 1024;
  static const _maxFieldLength = 4096;
  static const _maxAlpnItems = 16;

  TunnelProfile parse(String input) {
    if (input.length > _maxLinkLength) {
      throw const VlessLinkFormatException('Ссылка больше 64 КБ');
    }
    final raw = input.trim();
    if (raw.isEmpty) {
      throw const VlessLinkFormatException('Вставьте ссылку профиля');
    }

    final separator = raw.indexOf('://');
    final scheme =
        separator < 1 ? '' : raw.substring(0, separator).trim().toLowerCase();
    return switch (scheme) {
      'vless' => const VlessLinkParser().parse(raw),
      'vmess' => _parseVmess(raw),
      'trojan' => _parseTrojan(raw),
      'ss' => _parseShadowsocks(raw),
      'socks' || 'socks5' => _parseSocks(raw),
      'http' => _parseHttp(raw, tls: false),
      'https' => _parseHttp(raw, tls: true),
      _ => throw const VlessLinkFormatException(
          'Поддерживаются vless://, vmess://, trojan://, ss://, '
          'socks5:// и http(s)://',
        ),
    };
  }

  TunnelProfile _parseTrojan(String raw) {
    final uri = _uri(raw, 'trojan');
    final password = _decode(uri.userInfo).trim();
    if (password.isEmpty) {
      throw const VlessLinkFormatException('В ссылке Trojan нет пароля');
    }
    final stream = _stream(uri, defaultSecurity: 'tls');
    return _profile(
      protocol: OutboundProtocol.trojan,
      name: _name(uri),
      address: uri.host,
      port: _port(uri, defaultPort: 443),
      password: password,
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
      sourceLink: raw,
    );
  }

  TunnelProfile _parseSocks(String raw) {
    final uri = _uri(raw, null);
    final credentials = _credentials(uri);
    _validateOptionalCredentials(credentials, 'SOCKS5');
    return _profile(
      protocol: OutboundProtocol.socks,
      name: _name(uri),
      address: uri.host,
      port: _port(uri, defaultPort: 1080),
      userId: credentials.user,
      password: credentials.password,
      sourceLink: raw,
    );
  }

  TunnelProfile _parseHttp(String raw, {required bool tls}) {
    final uri = _uri(raw, tls ? 'https' : 'http');
    final credentials = _credentials(uri);
    _validateOptionalCredentials(credentials, 'HTTP');
    final stream = _stream(uri, defaultSecurity: tls ? 'tls' : 'none');
    return _profile(
      protocol: OutboundProtocol.http,
      name: _name(uri),
      address: uri.host,
      port: _port(uri, defaultPort: tls ? 443 : 80),
      userId: credentials.user,
      password: credentials.password,
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
      sourceLink: raw,
    );
  }

  TunnelProfile _parseVmess(String raw) {
    final payload = _withoutQueryAndFragment(raw.substring('vmess://'.length));
    if (payload.isEmpty) {
      throw const VlessLinkFormatException('В ссылке VMess нет данных');
    }
    final decoded = _base64Text(payload, 'VMess');
    Object? decodedJson;
    try {
      decodedJson = jsonDecode(decoded);
    } on FormatException {
      throw const VlessLinkFormatException(
          'VMess-ссылка содержит неверный JSON');
    }
    if (decodedJson is! Map) {
      throw const VlessLinkFormatException(
          'VMess-ссылка содержит неверный JSON');
    }
    final value = Map<String, Object?>.from(decodedJson);
    final address = _value(value, 'add').trim();
    final userId = _value(value, 'id').trim();
    if (address.isEmpty || userId.isEmpty) {
      throw const VlessLinkFormatException(
          'В ссылке VMess нет адреса или UUID');
    }
    final port = _intValue(value, 'port', fallback: 443);
    _validatePort(port);
    final alterId = _value(value, 'aid', alternate: 'alterId').trim();
    if (alterId.isNotEmpty && alterId != '0') {
      throw const VlessLinkFormatException(
        'VMess с alterId больше 0 не поддерживается текущим Xray',
      );
    }

    final transport =
        _normalizeTransport(_value(value, 'net', fallback: 'tcp'));
    final headerType = _value(value, 'type').trim().toLowerCase();
    if (transport == 'raw' &&
        headerType.isNotEmpty &&
        headerType != 'none' &&
        headerType != 'tcp') {
      throw const VlessLinkFormatException(
        'VMess с TCP-заголовком поддержать нельзя без изменения профиля',
      );
    }
    final security = _normalizeSecurity(
      _value(value, 'tls', alternate: 'security', fallback: 'none'),
    );
    final realityPassword = _value(value, 'pbk', alternate: 'publicKey');
    if (security == 'reality' && realityPassword.trim().isEmpty) {
      throw const VlessLinkFormatException(
          'Для VMess REALITY нужен параметр pbk');
    }

    final vmessSecurity =
        _normalizeVmessSecurity(_value(value, 'scy', fallback: 'auto'));
    final name = _value(value, 'ps').trim();
    final alpn = _listValue(value['alpn']);
    return _profile(
      protocol: OutboundProtocol.vmess,
      name: name.isEmpty ? address : name,
      address: address,
      port: port,
      userId: userId,
      vmessSecurity: vmessSecurity,
      security: security,
      transport: transport,
      serverName: _value(value, 'sni', alternate: 'serverName'),
      fingerprint: _value(value, 'fp', fallback: 'chrome'),
      realityPassword: realityPassword,
      shortId: _value(value, 'sid'),
      spiderX: _value(value, 'spx'),
      path: _value(value, 'path'),
      host: _value(value, 'host'),
      serviceName: _value(value, 'serviceName'),
      grpcMode: _value(value, 'mode'),
      alpn: alpn,
      allowInsecure:
          _boolValue(value['allowInsecure']) || _boolValue(value['insecure']),
      sourceLink: raw,
    );
  }

  TunnelProfile _parseShadowsocks(String raw) {
    final body = raw.substring('ss://'.length);
    final payload = _withoutQueryAndFragment(body);
    if (payload.isEmpty) {
      throw const VlessLinkFormatException('В ссылке Shadowsocks нет данных');
    }

    Uri uri;
    if (payload.contains('@')) {
      uri = _uri(raw, 'ss');
    } else {
      final decoded = _base64Text(payload, 'Shadowsocks');
      final suffixStart = body.indexOf(RegExp(r'[?#]'));
      final suffix = suffixStart < 0 ? '' : body.substring(suffixStart);
      uri = _uri('ss://$decoded$suffix', 'ss');
    }
    final plugin = uri.queryParameters['plugin']?.trim();
    if (plugin != null && plugin.isNotEmpty) {
      throw const VlessLinkFormatException(
        'Shadowsocks plugin не поддерживается в текущей сборке Xray',
      );
    }

    var credentials = _decode(uri.userInfo).trim();
    if (!credentials.contains(':')) {
      credentials = _base64Text(credentials, 'Shadowsocks');
    }
    final separator = credentials.indexOf(':');
    if (separator < 1 || separator == credentials.length - 1) {
      throw const VlessLinkFormatException(
        'В ссылке Shadowsocks нет метода или пароля',
      );
    }
    return _profile(
      protocol: OutboundProtocol.shadowsocks,
      name: _name(uri),
      address: uri.host,
      port: _port(uri, defaultPort: 8388),
      encryption: credentials.substring(0, separator),
      password: credentials.substring(separator + 1),
      sourceLink: raw,
    );
  }

  TunnelProfile _profile({
    required OutboundProtocol protocol,
    required String name,
    required String address,
    required int port,
    required String sourceLink,
    String userId = '',
    String password = '',
    String vmessSecurity = 'auto',
    String encryption = 'none',
    String security = 'none',
    String transport = 'raw',
    String serverName = '',
    String fingerprint = 'chrome',
    String realityPassword = '',
    String shortId = '',
    String spiderX = '',
    String path = '',
    String host = '',
    String serviceName = '',
    String grpcMode = '',
    List<String> alpn = const [],
    bool allowInsecure = false,
  }) {
    _require(address, _maxAddressLength, 'Адрес сервера');
    _require(name, _maxNameLength, 'Имя профиля');
    _require(userId, _maxFieldLength, 'Идентификатор');
    _require(password, _maxFieldLength, 'Пароль');
    _require(encryption, _maxFieldLength, 'Шифрование');
    _require(vmessSecurity, _maxFieldLength, 'VMess security');
    _require(security, _maxFieldLength, 'Security');
    _require(transport, _maxFieldLength, 'Transport');
    _require(serverName, _maxFieldLength, 'SNI');
    _require(fingerprint, _maxFieldLength, 'Fingerprint');
    _require(realityPassword, _maxFieldLength, 'REALITY key');
    _require(shortId, _maxFieldLength, 'Short ID');
    _require(spiderX, _maxFieldLength, 'Spider X');
    _require(path, _maxFieldLength, 'Path');
    _require(host, _maxFieldLength, 'Host');
    _require(serviceName, _maxFieldLength, 'Service name');
    _require(grpcMode, _maxFieldLength, 'gRPC mode');
    if (alpn.length > _maxAlpnItems ||
        alpn.any((item) => item.length > _maxFieldLength)) {
      throw const VlessLinkFormatException('Некорректный список ALPN');
    }
    _validatePort(port);

    final canonical = jsonEncode(<String, Object?>{
      'protocol': protocol.storageValue,
      'address': address.toLowerCase(),
      'port': port,
      'userId': userId,
      'password': password,
      'vmessSecurity': vmessSecurity,
      'encryption': encryption,
      'security': security,
      'transport': transport,
      'serverName': serverName.toLowerCase(),
      'fingerprint': fingerprint,
      'realityPassword': realityPassword,
      'shortId': shortId,
      'spiderX': spiderX,
      'path': path,
      'host': host.toLowerCase(),
      'serviceName': serviceName,
      'grpcMode': grpcMode,
      'alpn': [...alpn]..sort(),
      'allowInsecure': allowInsecure,
    });
    return TunnelProfile(
      id: sha256.convert(utf8.encode(canonical)).toString().substring(0, 32),
      name: name,
      address: address,
      port: port,
      userId: userId,
      password: password,
      outboundProtocol: protocol,
      vmessSecurity: vmessSecurity,
      encryption: encryption,
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
      sourceLink: sourceLink,
    );
  }

  Uri _uri(String raw, String? expectedScheme) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (expectedScheme != null &&
            uri.scheme.toLowerCase() != expectedScheme) ||
        uri.host.trim().isEmpty) {
      throw const VlessLinkFormatException(
          'В ссылке нет корректного адреса сервера');
    }
    _require(uri.host, _maxAddressLength, 'Адрес сервера');
    return uri;
  }

  ({String user, String password}) _credentials(Uri uri) {
    final value = _decode(uri.userInfo);
    if (value.isEmpty) return (user: '', password: '');
    final separator = value.indexOf(':');
    if (separator < 0) return (user: value, password: '');
    return (
      user: value.substring(0, separator),
      password: value.substring(separator + 1),
    );
  }

  void _validateOptionalCredentials(
    ({String user, String password}) credentials,
    String protocol,
  ) {
    if (credentials.user.isEmpty != credentials.password.isEmpty) {
      throw VlessLinkFormatException(
        'Для $protocol нужны одновременно имя пользователя и пароль',
      );
    }
  }

  ({
    String security,
    String transport,
    String serverName,
    String fingerprint,
    String realityPassword,
    String shortId,
    String spiderX,
    String path,
    String host,
    String serviceName,
    String grpcMode,
    List<String> alpn,
    bool allowInsecure,
  }) _stream(Uri uri, {required String defaultSecurity}) {
    final query = uri.queryParameters;
    final security = _normalizeSecurity(query['security'] ?? defaultSecurity);
    final transport = _normalizeTransport(query['type'] ?? 'tcp');
    final realityPassword = query['pbk'] ?? query['password'] ?? '';
    if (security == 'reality' && realityPassword.trim().isEmpty) {
      throw const VlessLinkFormatException('Для REALITY нужен параметр pbk');
    }
    return (
      security: security,
      transport: transport,
      serverName: query['sni'] ?? query['serverName'] ?? '',
      fingerprint: query['fp'] ?? 'chrome',
      realityPassword: realityPassword,
      shortId: query['sid'] ?? '',
      spiderX: query['spx'] ?? '',
      path: query['path'] ?? '',
      host: query['host'] ?? '',
      serviceName: query['serviceName'] ?? query['service_name'] ?? '',
      grpcMode: query['mode'] ?? '',
      alpn: _splitCsv(query['alpn']),
      allowInsecure:
          _boolValue(query['allowInsecure']) || _boolValue(query['insecure']),
    );
  }

  int _port(Uri uri, {required int defaultPort}) {
    try {
      final port = uri.hasPort ? uri.port : defaultPort;
      _validatePort(port);
      return port;
    } on FormatException {
      throw const VlessLinkFormatException('Некорректный порт профиля');
    }
  }

  String _name(Uri uri) {
    final name = _decode(uri.fragment).trim();
    _require(name, _maxNameLength, 'Имя профиля');
    return name.isEmpty ? uri.host : name;
  }

  String _normalizeTransport(String value) =>
      switch (value.trim().toLowerCase()) {
        '' || 'tcp' || 'raw' => 'raw',
        'ws' || 'websocket' => 'websocket',
        'grpc' => 'grpc',
        'xhttp' || 'splithttp' => 'xhttp',
        'httpupgrade' => 'httpupgrade',
        final unsupported => throw VlessLinkFormatException(
            'Пока не поддерживается transport=$unsupported',
          ),
      };

  String _normalizeSecurity(String value) {
    final security = value.trim().toLowerCase();
    if ({'none', 'tls', 'reality'}.contains(security)) return security;
    throw VlessLinkFormatException('Пока не поддерживается security=$security');
  }

  String _normalizeVmessSecurity(String value) {
    final security = value.trim().toLowerCase();
    if ({'auto', 'aes-128-gcm', 'chacha20-poly1305'}.contains(security)) {
      return security;
    }
    throw VlessLinkFormatException(
        'Пока не поддерживается VMess scy=$security');
  }

  List<String> _splitCsv(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final items = value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (items.length > _maxAlpnItems) {
      throw const VlessLinkFormatException('Слишком много значений ALPN');
    }
    return items;
  }

  List<String> _listValue(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return _splitCsv(value?.toString());
  }

  String _value(
    Map<String, Object?> values,
    String key, {
    String? alternate,
    String fallback = '',
  }) {
    final value = values[key] ?? (alternate == null ? null : values[alternate]);
    return value?.toString() ?? fallback;
  }

  int _intValue(
    Map<String, Object?> values,
    String key, {
    required int fallback,
  }) {
    final value = values[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _boolValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      throw const VlessLinkFormatException(
          'Ссылка содержит неверное кодирование');
    }
  }

  String _base64Text(String value, String protocol) {
    final normalized = _decode(value)
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll(RegExp(r'\s'), '');
    if (normalized.isEmpty) {
      throw VlessLinkFormatException('В ссылке $protocol нет данных');
    }
    final padded = normalized.padRight(
      normalized.length + (4 - normalized.length % 4) % 4,
      '=',
    );
    try {
      return utf8.decode(base64.decode(padded));
    } on FormatException {
      throw VlessLinkFormatException('В ссылке $protocol неверный Base64');
    }
  }

  String _withoutQueryAndFragment(String value) {
    final index = value.indexOf(RegExp(r'[?#]'));
    return index < 0 ? value : value.substring(0, index);
  }

  void _require(String value, int maxLength, String fieldName) {
    if (value.length > maxLength) {
      throw VlessLinkFormatException('$fieldName слишком длинное');
    }
  }

  void _validatePort(int port) {
    if (port < 1 || port > 65535) {
      throw const VlessLinkFormatException('Порт должен быть от 1 до 65535');
    }
  }
}
