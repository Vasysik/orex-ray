import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/xray_json_codec.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  const codec = XrayJsonCodec();

  test('imports a complete modern Xray config and skips system outbounds', () {
    final result = codec.decode(jsonEncode({
      'outbounds': [
        {
          'tag': 'Amsterdam',
          'protocol': 'vless',
          'settings': {
            'address': 'nl.example.com',
            'port': 443,
            'id': '11111111-1111-4111-8111-111111111111',
            'encryption': 'none',
            'flow': 'xtls-rprx-vision',
          },
          'streamSettings': {
            'network': 'raw',
            'security': 'reality',
            'realitySettings': {
              'serverName': 'www.example.com',
              'fingerprint': 'chrome',
              'publicKey': 'public-key',
              'shortId': 'abcd',
            },
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
    }));

    expect(result.skippedUnsupported, 0);
    expect(result.profiles, hasLength(1));
    final profile = result.profiles.single;
    expect(profile.name, 'Amsterdam');
    expect(profile.outboundProtocol, OutboundProtocol.vless);
    expect(profile.address, 'nl.example.com');
    expect(profile.port, 443);
    expect(profile.flow, 'xtls-rprx-vision');
    expect(profile.security, 'reality');
    expect(profile.realityPassword, 'public-key');
  });

  test('imports arrays of configs and traditional vnext/servers settings', () {
    final result = codec.decode(jsonEncode([
      {
        'remarks': 'VMess old style',
        'outbounds': [
          {
            'protocol': 'vmess',
            'settings': {
              'vnext': [
                {
                  'address': 'vmess.example.com',
                  'port': 443,
                  'users': [
                    {
                      'id': '22222222-2222-4222-8222-222222222222',
                      'security': 'auto',
                    }
                  ],
                }
              ],
            },
            'streamSettings': {
              'network': 'ws',
              'security': 'tls',
              'wsSettings': {
                'path': '/socket',
                'headers': {'Host': 'cdn.example.com'},
              },
              'tlsSettings': {
                'serverName': 'cdn.example.com',
                'alpn': ['h2', 'http/1.1'],
              },
            },
          }
        ],
      },
      {
        'protocol': 'shadowsocks',
        'tag': 'SS',
        'settings': {
          'servers': [
            {
              'address': 'ss.example.com',
              'port': 8388,
              'method': 'aes-256-gcm',
              'password': 'secret',
            }
          ],
        },
      }
    ]));

    expect(result.profiles, hasLength(2));
    final vmess = result.profiles.first;
    expect(vmess.name, 'VMess old style');
    expect(vmess.outboundProtocol, OutboundProtocol.vmess);
    expect(vmess.transport, 'websocket');
    expect(vmess.path, '/socket');
    expect(vmess.host, 'cdn.example.com');
    expect(vmess.security, 'tls');
    expect(vmess.alpn, ['h2', 'http/1.1']);

    final ss = result.profiles.last;
    expect(ss.name, 'SS');
    expect(ss.outboundProtocol, OutboundProtocol.shadowsocks);
    expect(ss.encryption, 'aes-256-gcm');
    expect(ss.password, 'secret');
  });

  test('exports one profile as config and many profiles as an array', () {
    const first = TunnelProfile(
      id: 'one',
      name: 'One',
      address: 'one.example.com',
      port: 443,
      userId: '11111111-1111-4111-8111-111111111111',
      security: 'tls',
      serverName: 'one.example.com',
    );
    const second = TunnelProfile(
      id: 'two',
      name: 'Two',
      address: 'two.example.com',
      port: 443,
      userId: '',
      outboundProtocol: OutboundProtocol.trojan,
      password: 'secret',
      security: 'tls',
      serverName: 'two.example.com',
    );

    final one = jsonDecode(codec.encodeProfiles([first]));
    expect(one, isA<Map>());
    final oneOutbounds = (one as Map)['outbounds'] as List;
    expect(
      oneOutbounds.whereType<Map>().firstWhere((item) => item['protocol'] == 'vless')['tag'],
      'One',
    );

    final forcedArray = jsonDecode(
      codec.encodeProfiles([first], forceArray: true),
    );
    expect(forcedArray, isA<List>());
    expect(forcedArray as List, hasLength(1));

    final manyText = codec.encodeProfiles([first, second]);
    final many = jsonDecode(manyText);
    expect(many, isA<List>());
    expect(many as List, hasLength(2));

    final roundTrip = codec.decode(manyText);
    expect(roundTrip.profiles, hasLength(2));
    expect(roundTrip.profiles.map((item) => item.name), ['One', 'Two']);
    expect(roundTrip.profiles[1].outboundProtocol, OutboundProtocol.trojan);
  });

  test('accepts UTF-8 BOM and uses config-level name with system outbounds', () {
    final json = jsonEncode({
      'remarks': 'Config name',
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'address': 'named.example.com',
            'port': 443,
            'id': '33333333-3333-4333-8333-333333333333',
            'encryption': 'none',
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
    });
    final result = codec.decode('\uFEFF$json');

    expect(result.profiles.single.name, 'Config name');
  });

  test('reserved profile names export without duplicate tags and round-trip', () {
    const names = [
      'direct',
      'block',
      'proxy',
      'proxy-1',
      'orexray-name-b64:literal',
    ];
    for (var index = 0; index < names.length; index++) {
      final name = names[index];
      final profile = TunnelProfile(
        id: 'reserved-$index',
        name: name,
        address: 'reserved-$index.example.com',
        port: 443,
        userId: '44444444-4444-4444-8444-444444444444',
      );

      final encoded = codec.encodeProfiles([profile]);
      final config = jsonDecode(encoded) as Map;
      final tags = (config['outbounds'] as List)
          .whereType<Map>()
          .map((item) => item['tag'])
          .whereType<String>()
          .toList(growable: false);
      expect(tags.toSet(), hasLength(tags.length));
      final routing = config['routing'] as Map;
      final rules = (routing['rules'] as List).whereType<Map>();
      final exportedProxyTag = tags.firstWhere(
        (tag) => tag != 'direct' && tag != 'block',
      );
      expect(
        rules.any((rule) => rule['outboundTag'] == exportedProxyTag),
        isTrue,
      );
      expect(codec.decode(encoded).profiles.single.name, name);
    }
  });

  test('rejects payloads that expand beyond the profile limit', () {
    final outbound = {
      'protocol': 'vless',
      'settings': {
        'address': 'many.example.com',
        'port': 443,
        'id': '66666666-6666-4666-8666-666666666666',
      },
    };

    expect(
      () => codec.decode(jsonEncode(List.filled(501, outbound))),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects excessively nested JSON arrays', () {
    Object value = {
      'protocol': 'vless',
      'settings': {
        'address': 'nested.example.com',
        'port': 443,
        'id': '55555555-5555-4555-8555-555555555555',
      },
    };
    for (var index = 0; index < 40; index++) {
      value = [value];
    }

    expect(
      () => codec.decode(jsonEncode(value)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported transport instead of silently changing it', () {
    expect(
      () => codec.decode(jsonEncode({
        'protocol': 'vless',
        'settings': {
          'address': 'example.com',
          'port': 443,
          'id': '11111111-1111-4111-8111-111111111111',
        },
        'streamSettings': {'network': 'kcp'},
      })),
      throwsA(isA<FormatException>()),
    );
  });
}
