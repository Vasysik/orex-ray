import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/proxy_link_parser.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  const parser = ProxyLinkParser();

  test('keeps VLESS parsing and canonical IDs compatible', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?encryption=none&security=tls&sni=example.com#VLESS';

    final legacy = const VlessLinkParser().parse(link);
    final imported = parser.parse(link);

    expect(imported.outboundProtocol, OutboundProtocol.vless);
    expect(imported.id, legacy.id);
    expect(imported.toJson().containsKey('outboundProtocol'), isFalse);
  });

  test('parses SOCKS5 and optional credentials', () {
    final profile = parser.parse(
      'socks5://alice:secret@socks.example:1080#Office',
    );

    expect(profile.outboundProtocol, OutboundProtocol.socks);
    expect(profile.name, 'Office');
    expect(profile.address, 'socks.example');
    expect(profile.port, 1080);
    expect(profile.userId, 'alice');
    expect(profile.password, 'secret');
  });

  test('round-trips a non-VLESS profile through persisted JSON', () {
    final profile = parser.parse('socks5://alice:secret@socks.example:1080');
    final restored = TunnelProfile.fromJson(profile.toJson());

    expect(restored.outboundProtocol, OutboundProtocol.socks);
    expect(restored.address, 'socks.example');
    expect(restored.userId, 'alice');
    expect(restored.password, 'secret');
  });

  test('parses HTTP and HTTPS proxy links', () {
    final http = parser.parse('http://proxy.example:3128#Plain');
    final https = parser.parse(
      'https://alice:secret@proxy.example:443?sni=proxy.example#TLS',
    );

    expect(http.outboundProtocol, OutboundProtocol.http);
    expect(http.security, 'none');
    expect(http.userId, isEmpty);
    expect(https.outboundProtocol, OutboundProtocol.http);
    expect(https.security, 'tls');
    expect(https.userId, 'alice');
    expect(https.password, 'secret');
    expect(https.serverName, 'proxy.example');
  });

  test('parses SIP002 Shadowsocks link', () {
    final profile = parser.parse(
      'ss://YWVzLTI1Ni1nY206c2VjcmV0@ss.example:8388#SS',
    );

    expect(profile.outboundProtocol, OutboundProtocol.shadowsocks);
    expect(profile.encryption, 'aes-256-gcm');
    expect(profile.password, 'secret');
    expect(profile.address, 'ss.example');
    expect(profile.port, 8388);
  });

  test('parses legacy base64 Shadowsocks link', () {
    final payload = base64.encode(
      utf8.encode('aes-128-gcm:legacy-secret@legacy-ss.example:8388'),
    );
    final profile = parser.parse('ss://$payload#Legacy');

    expect(profile.outboundProtocol, OutboundProtocol.shadowsocks);
    expect(profile.name, 'Legacy');
    expect(profile.encryption, 'aes-128-gcm');
    expect(profile.password, 'legacy-secret');
    expect(profile.address, 'legacy-ss.example');
  });

  test('parses Trojan TLS link with WebSocket transport', () {
    final profile = parser.parse(
      'trojan://secret@trojan.example:443?security=tls&type=ws'
      '&sni=cdn.example&path=%2Fsocket#Trojan',
    );

    expect(profile.outboundProtocol, OutboundProtocol.trojan);
    expect(profile.password, 'secret');
    expect(profile.security, 'tls');
    expect(profile.transport, 'websocket');
    expect(profile.serverName, 'cdn.example');
    expect(profile.path, '/socket');
  });

  test('parses a current VMess base64 JSON link', () {
    final payload = base64.encode(
      utf8.encode(jsonEncode(<String, Object?>{
        'v': '2',
        'ps': 'VMess TLS',
        'add': 'vmess.example',
        'port': '443',
        'id': '11111111-1111-4111-8111-111111111111',
        'aid': '0',
        'scy': 'auto',
        'net': 'ws',
        'type': 'none',
        'host': 'cdn.example',
        'path': '/ws',
        'tls': 'tls',
        'sni': 'cdn.example',
        'alpn': 'h2,http/1.1',
      })),
    );

    final profile = parser.parse('vmess://$payload');

    expect(profile.outboundProtocol, OutboundProtocol.vmess);
    expect(profile.name, 'VMess TLS');
    expect(profile.userId, '11111111-1111-4111-8111-111111111111');
    expect(profile.vmessSecurity, 'auto');
    expect(profile.transport, 'websocket');
    expect(profile.security, 'tls');
    expect(profile.alpn, ['h2', 'http/1.1']);
  });

  test('rejects a Shadowsocks plugin that the config builder cannot run', () {
    expect(
      () => parser.parse(
        'ss://YWVzLTI1Ni1nY206c2VjcmV0@ss.example:8388?plugin=v2ray-plugin',
      ),
      throwsA(isA<VlessLinkFormatException>()),
    );
  });
}
