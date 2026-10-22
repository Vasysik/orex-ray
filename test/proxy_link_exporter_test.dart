import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/proxy_link_exporter.dart';
import 'package:orex_ray/core/profiles/proxy_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  const serializer = ProxyLinkExporter();
  const parser = ProxyLinkParser();
  const uuid = '11111111-1111-4111-8111-111111111111';

  TunnelProfile profile(OutboundProtocol protocol, {
    String address = 'proxy.example',
    String name = 'Тест #1',
    String security = 'tls',
    String transport = 'websocket',
  }) => TunnelProfile(
        id: 'local-id',
        name: name,
        address: address,
        port: 8443,
        userId: switch (protocol) {
          OutboundProtocol.vless || OutboundProtocol.vmess => uuid,
          OutboundProtocol.socks || OutboundProtocol.http => 'user:name',
          _ => '',
        },
        password: switch (protocol) {
          OutboundProtocol.vless || OutboundProtocol.vmess => '',
          _ => 'p:@/#?асс',
        },
        outboundProtocol: protocol,
        vmessSecurity: 'aes-128-gcm',
        encryption: protocol == OutboundProtocol.shadowsocks
            ? 'aes-256-gcm'
            : 'none',
        security: protocol == OutboundProtocol.socks ||
                protocol == OutboundProtocol.shadowsocks
            ? 'none'
            : security,
        transport: protocol == OutboundProtocol.socks ||
                protocol == OutboundProtocol.shadowsocks
            ? 'raw'
            : transport,
        serverName: 'sni.example',
        fingerprint: 'chrome',
        path: '/wss?session=x',
        host: 'cdn.example',
        alpn: const ['h2', 'http/1.1'],
        allowInsecure: false,
        sourceLink: 'vless://old-and-now-invalid',
      );

  test('share-links use currently edited settings, not stale sourceLink', () {
    final updated = profile(OutboundProtocol.vless, address: 'new.example')
        .copyWith(flow: 'xtls-rprx-vision');
    final link = serializer.export(updated);
    expect(link, startsWith('vless://'));
    expect(link, contains('new.example:8443'));
    expect(link, contains('flow=xtls-rprx-vision'));
    expect(link, isNot(contains('old-and-now-invalid')));
    final imported = parser.parse(link);
    expect(imported.address, updated.address);
    expect(imported.name, updated.name);
    expect(imported.flow, updated.flow);
    expect(imported.transport, updated.transport);
    expect(imported.path, updated.path);
    expect(imported.alpn, updated.alpn);
  });

  for (final protocol in OutboundProtocol.values) {
    test('$protocol exports a link that OrexRay can re-import', () {
      final original = profile(protocol);
      final exported = serializer.export(original);
      final imported = parser.parse(exported);
      expect(imported.outboundProtocol, protocol);
      expect(imported.name, original.name);
      expect(imported.address, original.address);
      expect(imported.port, original.port);
      expect(imported.userId, original.userId);
      expect(imported.password, original.password);
      if (protocol == OutboundProtocol.vmess) {
        expect(imported.vmessSecurity, original.vmessSecurity);
      }
      if (protocol == OutboundProtocol.shadowsocks) {
        expect(imported.encryption, original.encryption);
      }
      if (protocol == OutboundProtocol.vless ||
          protocol == OutboundProtocol.vmess ||
          protocol == OutboundProtocol.trojan ||
          protocol == OutboundProtocol.http) {
        expect(imported.security, original.security);
        expect(imported.transport, original.transport);
        expect(imported.serverName, original.serverName);
        expect(imported.path, original.path);
        expect(imported.host, original.host);
        expect(imported.alpn, original.alpn);
      }
    });
  }

  test('VLESS REALITY preserves public key, short ID and gRPC', () {
    final original = profile(
      OutboundProtocol.vless,
      address: '2001:db8::1',
      security: 'reality',
      transport: 'grpc',
    ).copyWith(
      realityPassword: 'public-key',
      shortId: 'abcd',
      serviceName: 'grpc-service',
      grpcMode: 'multi',
    );
    final link = serializer.export(original);
    expect(link, contains('@[2001:db8::1]:8443'));
    final imported = parser.parse(link);
    expect(imported.security, 'reality');
    expect(imported.realityPassword, original.realityPassword);
    expect(imported.shortId, original.shortId);
    expect(imported.serviceName, original.serviceName);
    expect(imported.grpcMode, original.grpcMode);
  });

  test('does not serialize incomplete profiles', () {
    expect(
      () => serializer.export(profile(OutboundProtocol.vless)
          .copyWith(address: '')),
      throwsA(isA<FormatException>()),
    );
  });
}
