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

  TunnelProfile parse(String input) {
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
    final decodedName = _decode(uri.fragment).trim();
    final name = decodedName.isEmpty ? uri.host : decodedName;

    final canonical = [
      decodedUserId,
      uri.host,
      port,
      security,
      transport,
      serverName,
      realityPassword,
      query['sid'] ?? '',
    ].join('|');
    final encodedId = base64Url
        .encode(utf8.encode(canonical))
        .replaceAll('=', '');
    final id = encodedId.length >= 24
        ? encodedId.substring(0, 24)
        : sha256.convert(utf8.encode(canonical)).toString().substring(0, 24);

    return TunnelProfile(
      id: id,
      name: name,
      address: uri.host,
      port: port,
      userId: decodedUserId,
      encryption: query['encryption']?.trim().isNotEmpty == true
          ? query['encryption']!.trim()
          : 'none',
      flow: query['flow'] ?? '',
      security: security,
      transport: transport,
      serverName: serverName,
      fingerprint: query['fp'] ?? 'chrome',
      realityPassword: realityPassword,
      shortId: query['sid'] ?? '',
      spiderX: query['spx'] ?? '',
      path: query['path'] ?? '',
      host: query['host'] ?? '',
      serviceName: query['serviceName'] ?? query['service_name'] ?? '',
      grpcMode: query['mode'] ?? '',
      alpn: _splitCsv(query['alpn']),
      allowInsecure: _parseBool(query['allowInsecure'] ?? query['insecure']),
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

  List<String> _splitCsv(String? value) => value == null || value.trim().isEmpty
      ? const []
      : value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);

  bool _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }
}
