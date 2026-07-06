import 'dart:convert';

import '../tunnel/tunnel_models.dart';

class XrayConfigBuilder {
  const XrayConfigBuilder();

  static const int socksPort = 20808;
  static const int httpPort = 20809;

  String buildWindowsTun(
    TunnelTarget target, {
    int mtu = 1500,
    List<String> dnsServers = const ['1.1.1.1', '8.8.8.8'],
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    String logLevel = 'error',
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
            'gateway': ['10.77.0.1/24'],
            if (dnsServers.isNotEmpty) 'dns': dnsServers,
            'autoSystemRoutingTable': ['0.0.0.0/0'],
            'autoOutboundsInterface': 'auto',
          },
          'sniffing': _sniffing(sniffingEnabled),
        },
      ],
      bypassPrivateNetworks: bypassPrivateNetworks,
      logLevel: logLevel,
    );
  }

  String buildAndroidTun(
    TunnelTarget target, {
    int mtu = 1500,
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    String logLevel = 'error',
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
      ],
      bypassPrivateNetworks: bypassPrivateNetworks,
      logLevel: logLevel,
    );
  }

  String buildLocalProxy(
    TunnelTarget target, {
    int socksPort = XrayConfigBuilder.socksPort,
    int httpPort = XrayConfigBuilder.httpPort,
    bool allowLan = false,
    bool bypassPrivateNetworks = true,
    bool sniffingEnabled = true,
    String logLevel = 'error',
  }) {
    final listen = allowLan ? '0.0.0.0' : '127.0.0.1';
    return _encode(
      target,
      inbounds: [
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
      ],
      bypassPrivateNetworks: bypassPrivateNetworks,
      logLevel: logLevel,
    );
  }

  String _encode(
    TunnelTarget target, {
    required List<Map<String, Object?>> inbounds,
    required bool bypassPrivateNetworks,
    required String logLevel,
  }) {
    final routeToTarget = target.isBalancer
        ? <String, Object?>{'balancerTag': 'orexray-balancer'}
        : <String, Object?>{'outboundTag': 'proxy'};

    final rules = <Map<String, Object?>>[
      if (bypassPrivateNetworks)
        {
          'type': 'field',
          'ip': _privateNetworks,
          'outboundTag': 'direct',
        },
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

    final routing = <String, Object?>{
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
      if (target.isBalancer)
        'balancers': [
          {
            'tag': 'orexray-balancer',
            'selector': ['proxy-'],
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
      if (target.balancer?.strategy == BalancerStrategy.leastPing)
        'observatory': {
          'subjectSelector': ['proxy-'],
          'probeURL': target.balancer!.probeUrl,
          'probeInterval': '${target.balancer!.probeIntervalSeconds}s',
          'enableConcurrency': true,
        },
      'policy': {
        'system': {
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'stats': <String, Object?>{},
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  Map<String, Object?> _proxyOutbound(
    TunnelProfile profile, {
    required String tag,
  }) {
    final settings = <String, Object?>{
      'address': profile.address,
      'port': profile.port,
      'id': profile.userId,
      'encryption': profile.encryption,
    };
    if (profile.flow.isNotEmpty) settings['flow'] = profile.flow;

    return {
      'tag': tag,
      'protocol': 'vless',
      'settings': settings,
      'streamSettings': _streamSettings(profile),
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
        if (profile.allowInsecure) 'allowInsecure': true,
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
