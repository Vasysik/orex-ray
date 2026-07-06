import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/xray/xray_config_builder.dart';

void main() {
  final profile = const VlessLinkParser().parse(
    'vless://11111111-1111-4111-8111-111111111111@example.com:443'
    '?encryption=none&flow=xtls-rprx-vision&security=reality'
    '&sni=www.microsoft.com&fp=chrome&pbk=public-key&sid=abcd&type=tcp'
    '#My%20Server',
  );

  test('builds Windows TUN config with current VLESS REALITY fields', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildWindowsTun(profile),
    ) as Map<String, dynamic>;
    final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
    final outbound = (json['outbounds'] as List).first as Map<String, dynamic>;
    final stream = outbound['streamSettings'] as Map<String, dynamic>;
    final reality = stream['realitySettings'] as Map<String, dynamic>;

    expect(inbound['protocol'], 'tun');
    expect(inbound['settings']['autoSystemRoutingTable'], ['0.0.0.0/0']);
    expect(outbound['protocol'], 'vless');
    expect(outbound['settings']['address'], 'example.com');
    expect(stream['network'], 'raw');
    expect(reality['password'], 'public-key');
    expect(reality.containsKey('publicKey'), isFalse);
    expect(json['stats'], isA<Map>());
  });

  test('builds Android external-fd TUN config without Windows route automation', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(profile),
    ) as Map<String, dynamic>;
    final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
    final settings = inbound['settings'] as Map<String, dynamic>;
    final policy = json['policy'] as Map<String, dynamic>;
    final system = policy['system'] as Map<String, dynamic>;

    expect(inbound['protocol'], 'tun');
    expect(settings.containsKey('gateway'), isFalse);
    expect(settings.containsKey('dns'), isFalse);
    expect(settings.containsKey('autoSystemRoutingTable'), isFalse);
    expect(settings.containsKey('autoOutboundsInterface'), isFalse);
    expect(system['statsOutboundUplink'], isTrue);
    expect(system['statsOutboundDownlink'], isTrue);
  });

  test('builds configurable local SOCKS and HTTP proxy inbounds', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildLocalProxy(
        profile,
        socksPort: 31080,
        httpPort: 31081,
        allowLan: true,
        sniffingEnabled: false,
        bypassPrivateNetworks: false,
        logLevel: 'info',
      ),
    ) as Map<String, dynamic>;
    final inbounds = json['inbounds'] as List<dynamic>;
    final routing = json['routing'] as Map<String, dynamic>;
    final rules = routing['rules'] as List<dynamic>;

    expect(inbounds, hasLength(2));
    expect(inbounds[0]['protocol'], 'socks');
    expect(inbounds[0]['listen'], '0.0.0.0');
    expect(inbounds[0]['port'], 31080);
    expect(inbounds[0]['sniffing']['enabled'], isFalse);
    expect(inbounds[1]['protocol'], 'http');
    expect(inbounds[1]['port'], 31081);
    expect(json['log']['loglevel'], 'info');
    expect(rules, hasLength(1));
  });
}
