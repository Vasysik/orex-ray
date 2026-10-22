import 'dart:convert';

import '../tunnel/tunnel_models.dart';

/// Serializes the current profile settings, not its potentially stale sourceLink.
/// The output uses the ordinary share-link formats accepted by ProxyLinkParser.
class ProxyLinkExporter {
  const ProxyLinkExporter();

  String export(TunnelProfile profile) {
    if (profile.address.trim().isEmpty ||
        profile.port < 1 ||
        profile.port > 65535) {
      throw const FormatException('У профиля нет корректного адреса или порта');
    }
    final address = _host(profile.address);
    final name = Uri.encodeComponent(profile.name);

    switch (profile.outboundProtocol) {
      case OutboundProtocol.vless:
        if (profile.userId.trim().isEmpty) {
          throw const FormatException('У VLESS-профиля отсутствует ID');
        }
        final query = _streamQuery(profile)..['encryption'] = profile.encryption;
        if (profile.flow.isNotEmpty) query['flow'] = profile.flow;
        return 'vless://${Uri.encodeComponent(profile.userId)}@'
            '$address:${profile.port}${_query(query)}#$name';
      case OutboundProtocol.vmess:
        if (profile.userId.trim().isEmpty) {
          throw const FormatException('У VMess-профиля отсутствует ID');
        }
        final payload = <String, Object?>{
          'v': '2',
          'ps': profile.name,
          'add': profile.address,
          'port': profile.port.toString(),
          'id': profile.userId,
          'aid': '0',
          'scy': profile.vmessSecurity,
          'net': _transport(profile.transport),
          'type': 'none',
          'tls': profile.security,
          'sni': profile.serverName,
          'fp': profile.fingerprint,
          'pbk': profile.realityPassword,
          'sid': profile.shortId,
          'spx': profile.spiderX,
          'path': profile.path,
          'host': profile.host,
          'serviceName': profile.serviceName,
          'mode': profile.grpcMode,
          'alpn': profile.alpn.join(','),
          'allowInsecure': profile.allowInsecure,
        };
        final encoded = base64Url
            .encode(utf8.encode(jsonEncode(payload)))
            .replaceAll('=', '');
        return 'vmess://$encoded';
      case OutboundProtocol.trojan:
        if (profile.password.isEmpty) {
          throw const FormatException('У Trojan-профиля отсутствует пароль');
        }
        return 'trojan://${Uri.encodeComponent(profile.password)}@'
            '$address:${profile.port}${_query(_streamQuery(profile))}#$name';
      case OutboundProtocol.shadowsocks:
        if (profile.password.isEmpty || profile.encryption.isEmpty) {
          throw const FormatException('У Shadowsocks отсутствует метод или пароль');
        }
        final auth = base64Url
            .encode(utf8.encode('${profile.encryption}:${profile.password}'))
            .replaceAll('=', '');
        return 'ss://$auth@$address:${profile.port}#$name';
      case OutboundProtocol.socks:
        return 'socks5://${_userInfo(profile)}$address:${profile.port}#$name';
      case OutboundProtocol.http:
        final scheme = profile.security == 'tls' ? 'https' : 'http';
        return '$scheme://${_userInfo(profile)}$address:${profile.port}'
            '${_query(_streamQuery(profile))}#$name';
    }
  }

  String _host(String address) {
    final host = address.trim();
    return host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  }

  String _userInfo(TunnelProfile profile) {
    if (profile.userId.isEmpty && profile.password.isEmpty) return '';
    if (profile.userId.isEmpty || profile.password.isEmpty) {
      throw const FormatException('Нужны одновременно логин и пароль прокси');
    }
    return '${Uri.encodeComponent(profile.userId)}:'
        '${Uri.encodeComponent(profile.password)}@';
  }

  String _transport(String value) => switch (value) {
        'raw' => 'tcp',
        'websocket' => 'ws',
        _ => value,
      };

  Map<String, String> _streamQuery(TunnelProfile profile) => <String, String>{
        'security': profile.security,
        'type': _transport(profile.transport),
        if (profile.serverName.isNotEmpty) 'sni': profile.serverName,
        if (profile.fingerprint.isNotEmpty) 'fp': profile.fingerprint,
        if (profile.realityPassword.isNotEmpty) 'pbk': profile.realityPassword,
        if (profile.shortId.isNotEmpty) 'sid': profile.shortId,
        if (profile.spiderX.isNotEmpty) 'spx': profile.spiderX,
        if (profile.path.isNotEmpty) 'path': profile.path,
        if (profile.host.isNotEmpty) 'host': profile.host,
        if (profile.serviceName.isNotEmpty) 'serviceName': profile.serviceName,
        if (profile.grpcMode.isNotEmpty) 'mode': profile.grpcMode,
        if (profile.alpn.isNotEmpty) 'alpn': profile.alpn.join(','),
        if (profile.allowInsecure) 'allowInsecure': '1',
      };

  String _query(Map<String, String> values) => values.isEmpty
      ? ''
      : '?${Uri(queryParameters: values).query}';
}
