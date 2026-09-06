import 'dart:convert';

import '../tunnel/tunnel_models.dart';

class XrayConfigBuilder {
  const XrayConfigBuilder();

  static const int socksPort = 20808;
  static const int httpPort = 20809;

  String buildWindowsTun(
    TunnelTarget target, {
    int mtu = 1500,
    List<String> dnsServers = const [],
    int socksPort = XrayConfigBuilder.socksPort,
    int httpPort = XrayConfigBuilder.httpPort,
    bool allowLan = false,
    bool localProxyInVpn = true,
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    bool geoRoutingEnabled = false,
    List<String> geoDirectRules = const [],
    List<String> geoProxyRules = const [],
    List<String> geoBlockRules = const [],
    String logLevel = 'error',
    String? balancerProbeUrl,
    int? apiPort,
    String? outboundInterface,
  }) {
    return _encode(
      target,
      inbounds: [
        {
          'tag': 'orexray-tun',
          'protocol': 'tun',
          'settings': {
            'name': 'OrexRay',
            // Xray 26.4.13 models TUN MTU as repeated uint32: one value is
            // duplicated internally for IPv4/IPv6 by the core.
            'mtu': [mtu],
            'gateway': ['10.77.0.1/24', 'fd77:6f72:6578::1/64'],
            if (dnsServers.isNotEmpty) 'dns': dnsServers,
            'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
            'autoOutboundsInterface':
                outboundInterface?.trim().isNotEmpty == true
                    ? outboundInterface!.trim()
                    : 'auto',
          },
          'sniffing': _sniffing(sniffingEnabled),
        },
        if (localProxyInVpn)
          ..._localProxyInbounds(
            socksPort: socksPort,
            httpPort: httpPort,
            allowLan: allowLan,
            sniffingEnabled: sniffingEnabled,
          ),
      ],
      bypassPrivateNetworks: bypassPrivateNetworks,
      geoRoutingEnabled: geoRoutingEnabled,
      geoDirectRules: geoDirectRules,
      geoProxyRules: geoProxyRules,
      geoBlockRules: geoBlockRules,
      logLevel: logLevel,
      balancerProbeUrl: balancerProbeUrl,
      apiPort: apiPort,
    );
  }

  String buildAndroidTun(
    TunnelTarget target, {
    int mtu = 1500,
    int socksPort = XrayConfigBuilder.socksPort,
    int httpPort = XrayConfigBuilder.httpPort,
    bool allowLan = false,
    bool localProxyInVpn = true,
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    bool geoRoutingEnabled = false,
    List<String> geoDirectRules = const [],
    List<String> geoProxyRules = const [],
    List<String> geoBlockRules = const [],
    String logLevel = 'error',
    String? balancerProbeUrl,
  }) {
    return _encode(
      target,
      inbounds: [
        {
          'tag': 'orexray-tun',
          'protocol': 'tun',
          'settings': {
            'name': 'OrexRay',
            'mtu': mtu,
          },
          'sniffing': _sniffing(sniffingEnabled),
        },
        if (localProxyInVpn)
          ..._localProxyInbounds(
            socksPort: socksPort,
            httpPort: httpPort,
            allowLan: allowLan,
            sniffingEnabled: sniffingEnabled,
          ),
      ],
      bypassPrivateNetworks: bypassPrivateNetworks,
      geoRoutingEnabled: geoRoutingEnabled,
      geoDirectRules: geoDirectRules,
      geoProxyRules: geoProxyRules,
      geoBlockRules: geoBlockRules,
      logLevel: logLevel,
      balancerProbeUrl: balancerProbeUrl,
      enableInboundStats: false,
    );
  }

  String buildLocalProxy(
    TunnelTarget target, {
    int socksPort = XrayConfigBuilder.socksPort,
    int httpPort = XrayConfigBuilder.httpPort,
    bool allowLan = false,
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    bool geoRoutingEnabled = false,
    List<String> geoDirectRules = const [],
    List<String> geoProxyRules = const [],
    List<String> geoBlockRules = const [],
    String logLevel = 'error',
    String? balancerProbeUrl,
    int? apiPort,
    bool enableInboundStats = true,
  }) {
    return _encode(
      target,
      inbounds: _localProxyInbounds(
        socksPort: socksPort,
        httpPort: httpPort,
        allowLan: allowLan,
        sniffingEnabled: sniffingEnabled,
      ),
      bypassPrivateNetworks: bypassPrivateNetworks,
      geoRoutingEnabled: geoRoutingEnabled,
      geoDirectRules: geoDirectRules,
      geoProxyRules: geoProxyRules,
      geoBlockRules: geoBlockRules,
      logLevel: logLevel,
      balancerProbeUrl: balancerProbeUrl,
      apiPort: apiPort,
      enableInboundStats: enableInboundStats,
    );
  }

  List<Map<String, Object?>> _localProxyInbounds({
    required int socksPort,
    required int httpPort,
    required bool allowLan,
    required bool sniffingEnabled,
  }) {
    final listen = allowLan ? '0.0.0.0' : '127.0.0.1';
    return [
      {
        'tag': 'orexray-socks',
        'listen': listen,
        'port': socksPort,
        'protocol': 'socks',
        'settings': {'udp': true},
        'sniffing': _sniffing(sniffingEnabled),
      },
      {
        'tag': 'orexray-http',
        'listen': listen,
        'port': httpPort,
        'protocol': 'http',
        'settings': <String, Object?>{},
        'sniffing': _sniffing(sniffingEnabled),
      },
    ];
  }

  String _encode(
    TunnelTarget target, {
    required List<Map<String, Object?>> inbounds,
    required bool bypassPrivateNetworks,
    required bool geoRoutingEnabled,
    required List<String> geoDirectRules,
    required List<String> geoProxyRules,
    required List<String> geoBlockRules,
    required String logLevel,
    String? balancerProbeUrl,
    int? apiPort,
    bool enableInboundStats = true,
  }) {
    final routeToTarget = target.isBalancer
        ? <String, Object?>{'balancerTag': 'orexray-balancer'}
        : <String, Object?>{'outboundTag': 'proxy'};

    final rules = <Map<String, Object?>>[
      if (geoRoutingEnabled)
        ..._geoRules(geoBlockRules, {'outboundTag': 'block'}),
      if (geoRoutingEnabled)
        ..._geoRules(geoDirectRules, {'outboundTag': 'direct'}),
      if (bypassPrivateNetworks)
        {
          'type': 'field',
          'ip': _privateNetworks,
          'outboundTag': 'direct',
        },
      if (geoRoutingEnabled) ..._geoRules(geoProxyRules, routeToTarget),
      {
        'type': 'field',
        'network': 'tcp,udp',
        ...routeToTarget,
      },
    ];

    final proxyOutbounds = target.isBalancer
        ? <Map<String, Object?>>[
            for (var i = 0; i < target.profiles.length; i++)
              _proxyOutbound(target.profiles[i], tag: 'proxy-$i'),
          ]
        : <Map<String, Object?>>[
            _proxyOutbound(target.primaryProfile, tag: 'proxy'),
          ];

    final fallbackTag = target.isBalancer ? _balancerFallbackTag(target) : null;
    final fallbackProfile = target.fallbackProfile;
    if (target.isBalancer && fallbackProfile != null) {
      proxyOutbounds.add(
        _proxyOutbound(fallbackProfile, tag: 'fallback-proxy'),
      );
    }

    final routing = <String, Object?>{
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
      if (target.isBalancer)
        'balancers': [
          {
            'tag': 'orexray-balancer',
            'selector': ['proxy-'],
            if (fallbackTag != null) 'fallbackTag': fallbackTag,
            'strategy': {
              'type': target.balancer!.strategy.storageValue,
            },
          },
        ],
    };

    final config = <String, Object?>{
      'log': {'loglevel': logLevel},
      'inbounds': inbounds,
      'outbounds': [
        ...proxyOutbounds,
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': routing,
      if (apiPort != null)
        'api': {
          'tag': 'orexray-api',
          'listen': '127.0.0.1:$apiPort',
          'services': ['StatsService'],
        },
      if (target.balancer?.strategy == BalancerStrategy.leastPing ||
          fallbackTag != null)
        'observatory': {
          'subjectSelector': ['proxy-'],
          'probeURL': balancerProbeUrl?.trim().isNotEmpty == true
              ? balancerProbeUrl!.trim()
              : target.balancer!.probeUrl,
          'probeInterval': '${target.balancer!.probeIntervalSeconds}s',
          'enableConcurrency': true,
        },
      'policy': {
        'system': {
          // Android reads per-outbound counters from the embedded core, while
          // Windows StatsService aggregates `inbound>>>orexray-*`. Keep the
          // inbound counters only where there is an actual consumer.
          'statsInboundUplink': enableInboundStats,
          'statsInboundDownlink': enableInboundStats,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'stats': <String, Object?>{},
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String? _balancerFallbackTag(TunnelTarget target) {
    final fallback = target.balancer?.fallbackTarget;
    if (fallback == null || fallback.isEmpty) return null;
    if (fallback == BalancerProfile.fallbackDirect) return 'direct';
    if (fallback == BalancerProfile.fallbackBlock) return 'block';

    final profileId = target.balancer?.fallbackProfileId;
    if (profileId == null) return null;
    if (target.fallbackProfile?.id == profileId) return 'fallback-proxy';
    return null;
  }

  List<Map<String, Object?>> _geoRules(
    List<String> values,
    Map<String, Object?> destination,
  ) {
    final ip = <String>[];
    final domain = <String>[];
    for (final value in values) {
      final rule = value.trim().toLowerCase();
      if (rule.startsWith('geoip:')) {
        ip.add(rule);
      } else if (rule.startsWith('geosite:')) {
        domain.add(rule);
      }
    }
    return [
      if (domain.isNotEmpty)
        {
          'type': 'field',
          'domain': domain,
          ...destination,
        },
      if (ip.isNotEmpty)
        {
          'type': 'field',
          'ip': ip,
          ...destination,
        },
    ];
  }

  Map<String, Object?> _proxyOutbound(
    TunnelProfile profile, {
    required String tag,
  }) {
    final settings = <String, Object?>{
      'address': profile.address,
      'port': profile.port,
    };
    switch (profile.outboundProtocol) {
      case OutboundProtocol.vless:
        settings
          ..['id'] = profile.userId
          ..['encryption'] = profile.encryption;
        if (profile.flow.isNotEmpty) settings['flow'] = profile.flow;
      case OutboundProtocol.vmess:
        settings
          ..['id'] = profile.userId
          ..['security'] = profile.vmessSecurity;
      case OutboundProtocol.trojan:
        settings['password'] = profile.password;
      case OutboundProtocol.shadowsocks:
        settings
          ..['method'] = profile.encryption
          ..['password'] = profile.password;
      case OutboundProtocol.socks || OutboundProtocol.http:
        if (profile.userId.isNotEmpty) settings['user'] = profile.userId;
        if (profile.password.isNotEmpty) settings['pass'] = profile.password;
    }

    final needsStreamSettings =
        profile.outboundProtocol == OutboundProtocol.vless ||
            profile.outboundProtocol == OutboundProtocol.vmess ||
            profile.outboundProtocol == OutboundProtocol.trojan ||
            profile.security != 'none' ||
            profile.transport != 'raw';
    return {
      'tag': tag,
      'protocol': profile.outboundProtocol.storageValue,
      'settings': settings,
      if (needsStreamSettings) 'streamSettings': _streamSettings(profile),
    };
  }

  Map<String, Object?> _streamSettings(TunnelProfile profile) {
    final settings = <String, Object?>{
      'network': profile.transport,
      'security': profile.security,
    };

    if (profile.transport == 'raw') {
      settings['rawSettings'] = {
        'header': {'type': 'none'},
      };
    } else if (profile.transport == 'websocket') {
      settings['wsSettings'] = {
        if (profile.path.isNotEmpty) 'path': profile.path,
        if (profile.host.isNotEmpty) 'host': profile.host,
      };
    } else if (profile.transport == 'grpc') {
      settings['grpcSettings'] = {
        if (profile.serviceName.isNotEmpty) 'serviceName': profile.serviceName,
        if (profile.grpcMode.toLowerCase() == 'multi') 'multiMode': true,
      };
    } else if (profile.transport == 'xhttp') {
      settings['xhttpSettings'] = {
        if (profile.path.isNotEmpty) 'path': profile.path,
        if (profile.host.isNotEmpty) 'host': profile.host,
      };
    } else if (profile.transport == 'httpupgrade') {
      settings['httpupgradeSettings'] = {
        if (profile.path.isNotEmpty) 'path': profile.path,
        if (profile.host.isNotEmpty) 'host': profile.host,
      };
    }

    if (profile.security == 'reality') {
      settings['realitySettings'] = {
        'serverName': profile.serverName,
        'fingerprint': profile.fingerprint,
        'password': profile.realityPassword,
        'shortId': profile.shortId,
        if (profile.spiderX.isNotEmpty) 'spiderX': profile.spiderX,
      };
    } else if (profile.security == 'tls') {
      settings['tlsSettings'] = {
        if (profile.serverName.isNotEmpty) 'serverName': profile.serverName,
        'fingerprint': profile.fingerprint,
        if (profile.alpn.isNotEmpty) 'alpn': profile.alpn,
      };
    }

    return settings;
  }

  static Map<String, Object?> _sniffing(bool enabled) => {
        'enabled': enabled,
        if (enabled) 'destOverride': ['http', 'tls', 'quic'],
      };

  static const _privateNetworks = <String>[
    '10.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '224.0.0.0/4',
    '240.0.0.0/4',
  ];
}
