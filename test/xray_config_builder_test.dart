import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/core/xray/xray_config_builder.dart';

void main() {
  final profile = const VlessLinkParser().parse(
    'vless://11111111-1111-4111-8111-111111111111@example.com:443'
    '?encryption=none&flow=xtls-rprx-vision&security=reality'
    '&sni=www.microsoft.com&fp=chrome&pbk=public-key&sid=abcd&type=tcp'
    '#My%20Server',
  );
  final target = TunnelTarget.single(profile);

  test('builds Windows TUN config with current VLESS REALITY fields', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildWindowsTun(target),
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
      const XrayConfigBuilder().buildAndroidTun(target),
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
        target,
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


  test('keeps local SOCKS and HTTP proxy available next to VPN TUN', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(target),
    ) as Map<String, dynamic>;
    final inbounds = json['inbounds'] as List<dynamic>;

    expect(inbounds, hasLength(3));
    expect(inbounds[0]['protocol'], 'tun');
    expect(inbounds[1]['protocol'], 'socks');
    expect(inbounds[2]['protocol'], 'http');
  });

  test('keeps parallel VPN proxies loopback-only by default', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        target,
        socksPort: 30808,
        httpPort: 30809,
      ),
    ) as Map<String, dynamic>;
    final inbounds = (json['inbounds'] as List).cast<Map<String, dynamic>>();

    expect(inbounds[1]['listen'], '127.0.0.1');
    expect(inbounds[1]['port'], 30808);
    expect(inbounds[2]['listen'], '127.0.0.1');
    expect(inbounds[2]['port'], 30809);
  });

  test('opens parallel VPN proxies on LAN only when explicitly requested', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        target,
        allowLan: true,
      ),
    ) as Map<String, dynamic>;
    final inbounds = (json['inbounds'] as List).cast<Map<String, dynamic>>();

    expect(inbounds[1]['listen'], '0.0.0.0');
    expect(inbounds[2]['listen'], '0.0.0.0');
  });

  test('can disable local proxy in VPN mode', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        target,
        localProxyInVpn: false,
      ),
    ) as Map<String, dynamic>;
    final inbounds = json['inbounds'] as List<dynamic>;

    expect(inbounds, hasLength(1));
    expect(inbounds.single['protocol'], 'tun');
  });

  test('builds GeoData block, direct and proxy rules', () {
    final json = jsonDecode(
      const XrayConfigBuilder().buildLocalProxy(
        target,
        geoRoutingEnabled: true,
        geoBlockRules: ['geosite:category-ads-all'],
        geoDirectRules: ['geoip:private', 'geosite:ru'],
        geoProxyRules: ['geosite:google'],
      ),
    ) as Map<String, dynamic>;
    final routing = json['routing'] as Map<String, dynamic>;
    final rules = (routing['rules'] as List).cast<Map<String, dynamic>>();

    expect(rules[0]['domain'], ['geosite:category-ads-all']);
    expect(rules[0]['outboundTag'], 'block');
    expect(
      rules.any((rule) =>
          rule['ip'] is List &&
          (rule['ip'] as List).contains('geoip:private') &&
          rule['outboundTag'] == 'direct'),
      isTrue,
    );
    expect(
      rules.any((rule) =>
          rule['domain'] is List &&
          (rule['domain'] as List).contains('geosite:google') &&
          rule['outboundTag'] == 'proxy'),
      isTrue,
    );
  });

  test('builds Xray balancer profile', () {
    final second = profile.copyWith(
      id: 'second',
      name: 'Second',
      address: 'second.example.com',
    );
    final balancer = BalancerProfile(
      id: 'balancer-1',
      name: 'Fast pool',
      memberIds: [profile.id, second.id],
      strategy: BalancerStrategy.leastPing,
      probeIntervalSeconds: 30,
    );
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        TunnelTarget.balancer(balancer, [profile, second]),
      ),
    ) as Map<String, dynamic>;
    final outbounds = json['outbounds'] as List<dynamic>;
    final routing = json['routing'] as Map<String, dynamic>;

    expect(outbounds[0]['tag'], 'proxy-0');
    expect(outbounds[1]['tag'], 'proxy-1');
    expect((routing['balancers'] as List).single['tag'], 'orexray-balancer');
    expect(json['observatory'], isA<Map>());
  });

  test('uses official Xray direct fallbackTag for balancers', () {
    final second = profile.copyWith(
      id: 'second-fallback-direct',
      name: 'Second',
      address: 'second.example.com',
    );
    final balancer = BalancerProfile(
      id: 'balancer-direct-fallback',
      name: 'Fallback direct',
      memberIds: [profile.id, second.id],
      strategy: BalancerStrategy.random,
      fallbackTarget: BalancerProfile.fallbackDirect,
    );
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        TunnelTarget.balancer(balancer, [profile, second]),
      ),
    ) as Map<String, dynamic>;
    final routing = json['routing'] as Map<String, dynamic>;
    final balancerConfig =
        (routing['balancers'] as List).single as Map<String, dynamic>;

    expect(balancerConfig['fallbackTag'], 'direct');
    expect(json['observatory'], isA<Map>());
  });

  test('uses a separate outbound for profile fallback', () {
    final second = profile.copyWith(
      id: 'second-fallback-profile',
      name: 'Second',
      address: 'second.example.com',
    );
    final fallback = profile.copyWith(
      id: 'fallback-profile',
      name: 'Fallback',
      address: 'fallback.example.com',
    );
    final balancer = BalancerProfile(
      id: 'balancer-profile-fallback',
      name: 'Profile fallback',
      memberIds: [profile.id, second.id],
      strategy: BalancerStrategy.roundRobin,
      fallbackTarget: BalancerProfile.fallbackProfile(fallback.id),
    );
    final json = jsonDecode(
      const XrayConfigBuilder().buildAndroidTun(
        TunnelTarget.balancer(
          balancer,
          [profile, second],
          fallbackProfile: fallback,
        ),
      ),
    ) as Map<String, dynamic>;
    final outbounds = (json['outbounds'] as List).cast<Map<String, dynamic>>();
    final routing = json['routing'] as Map<String, dynamic>;
    final balancerConfig =
        (routing['balancers'] as List).single as Map<String, dynamic>;

    expect(balancerConfig['fallbackTag'], 'fallback-proxy');
    expect(
      outbounds.any((outbound) => outbound['tag'] == 'fallback-proxy'),
      isTrue,
    );
  });

}
