import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../tunnel/tunnel_models.dart';

class VlessLinkFormatException implements Exception {
  const VlessLinkFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VlessLinkParser {
  const VlessLinkParser();

  static const _maxLinkLength = 64 * 1024;
  static const _maxNameLength = 256;
  static const _maxAddressLength = 1024;
  static const _maxFieldLength = 4096;
  static const _maxAlpnItems = 16;

  TunnelProfile parse(String input) {
    if (input.length > _maxLinkLength) {
      throw const VlessLinkFormatException('VLESS-ссылка больше 64 КБ');
    }

    final raw = input.trim();
    if (raw.isEmpty) {
      throw const VlessLinkFormatException('Вставьте ссылку vless://');
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'vless') {
      throw const VlessLinkFormatException('Ссылка должна начинаться с vless://');
    }
    if (uri.userInfo.trim().isEmpty) {
      throw const VlessLinkFormatException('В ссылке нет VLESS ID');
    }
    if (uri.host.trim().isEmpty) {
      throw const VlessLinkFormatException('В ссылке нет адреса сервера');
    }

    _requireMaxLength(uri.host, _maxAddressLength, 'Адрес сервера');
    for (final entry in uri.queryParameters.entries) {
      _requireMaxLength(entry.key, 256, 'Имя параметра');
      _requireMaxLength(entry.value, _maxFieldLength, 'Параметр ${entry.key}');
    }

    final query = uri.queryParameters;
    final security = (query['security'] ?? 'none').toLowerCase();
    final transport = _normalizeTransport(query['type'] ?? 'tcp');
    final port = uri.hasPort ? uri.port : 443;
    if (port < 1 || port > 65535) {
      throw const VlessLinkFormatException('Порт должен быть от 1 до 65535');
    }

    final realityPassword = query['pbk'] ?? query['password'] ?? '';
    final serverName = query['sni'] ?? query['serverName'] ?? '';

    if (security == 'reality' && realityPassword.isEmpty) {
      throw const VlessLinkFormatException(
        'Для REALITY в ссылке нужен параметр pbk',
      );
    }
    if (!{'none', 'tls', 'reality'}.contains(security)) {
      throw VlessLinkFormatException('Пока не поддерживаем security=$security');
    }

    final decodedUserId = _decode(uri.userInfo).trim();
    if (decodedUserId.isEmpty) {
      throw const VlessLinkFormatException('В ссылке пустой VLESS ID');
    }
    _requireMaxLength(decodedUserId, _maxFieldLength, 'VLESS ID');

    final decodedName = _decode(uri.fragment).trim();
    _requireMaxLength(decodedName, _maxNameLength, 'Имя профиля');
    final name = decodedName.isEmpty ? uri.host : decodedName;

    final encryption = query['encryption']?.trim().isNotEmpty == true
        ? query['encryption']!.trim()
        : 'none';
    final flow = query['flow'] ?? '';
    final fingerprint = query['fp'] ?? 'chrome';
    final shortId = query['sid'] ?? '';
    final spiderX = query['spx'] ?? '';
    final path = query['path'] ?? '';
    final host = query['host'] ?? '';
    final serviceName = query['serviceName'] ?? query['service_name'] ?? '';
    final grpcMode = query['mode'] ?? '';
    final alpn = _splitCsv(query['alpn']);
    final allowInsecure = _parseBool(
      query['allowInsecure'] ?? query['insecure'],
    );

    final canonical = jsonEncode(<String, Object?>{
      'address': uri.host.toLowerCase(),
      'port': port,
      'userId': decodedUserId,
      'encryption': encryption,
      'flow': flow,
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
    final id = sha256.convert(utf8.encode(canonical)).toString().substring(0, 32);

    return TunnelProfile(
      id: id,
      name: name,
      address: uri.host,
      port: port,
      userId: decodedUserId,
      encryption: encryption,
      flow: flow,
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
      sourceLink: raw,
    );
  }

  String _normalizeTransport(String value) => switch (value.toLowerCase()) {
        'tcp' || 'raw' => 'raw',
        'ws' || 'websocket' => 'websocket',
        'grpc' => 'grpc',
        'xhttp' || 'splithttp' => 'xhttp',
        'httpupgrade' => 'httpupgrade',
        final unsupported => throw VlessLinkFormatException(
            'Пока не поддерживаем transport=$unsupported',
          ),
      };

  String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      throw const VlessLinkFormatException('Ссылка содержит неверное кодирование');
    }
  }

  List<String> _splitCsv(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final items = value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (items.length > _maxAlpnItems) {
      throw const VlessLinkFormatException('Слишком много ALPN-значений');
    }
    return items;
  }

  bool _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  void _requireMaxLength(String value, int maxLength, String fieldName) {
    if (value.length > maxLength) {
      throw VlessLinkFormatException('$fieldName слишком длинный');
    }
  }
}
