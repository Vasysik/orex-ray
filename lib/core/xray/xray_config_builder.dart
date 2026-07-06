import 'dart:convert';

import '../tunnel/tunnel_models.dart';

class XrayConfigBuilder {
  const XrayConfigBuilder();

  static const int socksPort = 20808;
  static const int httpPort = 20809;

  String buildWindowsTun(TunnelProfile profile) {
    return _encode(
      profile,
      inbounds: [
        {
          'tag': 'orexray-tun',
          'protocol': 'tun',
          'settings': {
            'name': 'OrexRay',
            'mtu': 1500,
            'gateway': ['10.77.0.1/24'],
            'dns': ['1.1.1.1', '8.8.8.8'],
            'autoSystemRoutingTable': ['0.0.0.0/0'],
            'autoOutboundsInterface': 'auto',
          },
          'sniffing': _sniffing,
        },
      ],
    );
  }

  String buildAndroidTun(TunnelProfile profile) {
    return _encode(
      profile,
      inbounds: [
        {
          'tag': 'orexray-tun',
          'protocol': 'tun',
          'settings': {
            'name': 'OrexRay',
            'mtu': 1500,
          },
          'sniffing': _sniffing,
        },
      ],
    );
  }

  String buildLocalProxy(TunnelProfile profile) {
    return _encode(
      profile,
      inbounds: [
        {
          'tag': 'orexray-socks',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': {
            'udp': true,
          },
          'sniffing': _sniffing,
        },
        {
          'tag': 'orexray-http',
          'listen': '127.0.0.1',
          'port': httpPort,
          'protocol': 'http',
          'settings': <String, Object?>{},
          'sniffing': _sniffing,
        },
      ],
    );
  }

  String _encode(
    TunnelProfile profile, {
    required List<Map<String, Object?>> inbounds,
  }) {
    final config = <String, Object?>{
      'log': {
        // Keep normal app runs quiet. Detailed Xray output is still captured by
        // the platform engine and surfaced when a connection actually fails.
        'loglevel': 'error',
      },
      'inbounds': inbounds,
      'outbounds': [
        _proxyOutbound(profile),
        {
          'tag': 'direct',
          'protocol': 'freedom',
        },
        {
          'tag': 'block',
          'protocol': 'blackhole',
        },
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'type': 'field',
            'ip': _privateNetworks,
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'network': 'tcp,udp',
            'outboundTag': 'proxy',
          },
        ],
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

  Map<String, Object?> _proxyOutbound(TunnelProfile profile) {
    final settings = <String, Object?>{
      'address': profile.address,
      'port': profile.port,
      'id': profile.userId,
      'encryption': profile.encryption,
    };
    if (profile.flow.isNotEmpty) {
      settings['flow'] = profile.flow;
    }

    return {
      'tag': 'proxy',
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

  static const _sniffing = <String, Object?>{
    'enabled': true,
    'destOverride': ['http', 'tls', 'quic'],
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
