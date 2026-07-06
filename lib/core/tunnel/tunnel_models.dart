enum ConnectionMode {
  vpnTun,
  systemProxy,
  localProxy;

  String get storageValue => switch (this) {
        ConnectionMode.vpnTun => 'vpn_tun',
        ConnectionMode.systemProxy => 'system_proxy',
        ConnectionMode.localProxy => 'local_proxy',
      };

  String get title => switch (this) {
        ConnectionMode.vpnTun => 'VPN',
        ConnectionMode.systemProxy => 'Системный прокси',
        ConnectionMode.localProxy => 'Локальный прокси',
      };

  String get shortTitle => switch (this) {
        ConnectionMode.vpnTun => 'VPN',
        ConnectionMode.systemProxy => 'Система',
        ConnectionMode.localProxy => 'Прокси',
      };

  String get description => switch (this) {
        ConnectionMode.vpnTun => 'Весь трафик устройства через защищённый туннель',
        ConnectionMode.systemProxy =>
          'Приложения Windows, использующие системный прокси',
        ConnectionMode.localProxy =>
          'Локальные SOCKS5 и HTTP точки входа для выбранных приложений',
      };

  static ConnectionMode? fromStorageValue(String? value) => switch (value) {
        'vpn_tun' => ConnectionMode.vpnTun,
        'system_proxy' => ConnectionMode.systemProxy,
        'local_proxy' => ConnectionMode.localProxy,
        _ => null,
      };
}

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class TunnelProfile {
  const TunnelProfile({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.userId,
    this.encryption = 'none',
    this.flow = '',
    this.security = 'none',
    this.transport = 'raw',
    this.serverName = '',
    this.fingerprint = 'chrome',
    this.realityPassword = '',
    this.shortId = '',
    this.spiderX = '',
    this.path = '',
    this.host = '',
    this.serviceName = '',
    this.grpcMode = '',
    this.alpn = const [],
    this.allowInsecure = false,
    this.sourceLink = '',
    this.latencyMs,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final String userId;
  final String encryption;
  final String flow;
  final String security;
  final String transport;
  final String serverName;
  final String fingerprint;
  final String realityPassword;
  final String shortId;
  final String spiderX;
  final String path;
  final String host;
  final String serviceName;
  final String grpcMode;
  final List<String> alpn;
  final bool allowInsecure;
  final String sourceLink;
  final int? latencyMs;

  String get endpoint => '$address:$port';

  String get protocol {
    final securityLabel = switch (security) {
      'reality' => 'REALITY',
      'tls' => 'TLS',
      _ => 'NONE',
    };
    return 'VLESS · $securityLabel';
  }

  String get transportLabel => switch (transport) {
        'raw' => 'RAW',
        'websocket' => 'WebSocket',
        'grpc' => 'gRPC',
        'xhttp' => 'XHTTP',
        'httpupgrade' => 'HTTPUpgrade',
        _ => transport.toUpperCase(),
      };

  TunnelProfile copyWith({
    String? id,
    String? name,
    String? address,
    int? port,
    String? userId,
    String? encryption,
    String? flow,
    String? security,
    String? transport,
    String? serverName,
    String? fingerprint,
    String? realityPassword,
    String? shortId,
    String? spiderX,
    String? path,
    String? host,
    String? serviceName,
    String? grpcMode,
    List<String>? alpn,
    bool? allowInsecure,
    String? sourceLink,
    int? latencyMs,
    bool clearLatency = false,
  }) {
    return TunnelProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      userId: userId ?? this.userId,
      encryption: encryption ?? this.encryption,
      flow: flow ?? this.flow,
      security: security ?? this.security,
      transport: transport ?? this.transport,
      serverName: serverName ?? this.serverName,
      fingerprint: fingerprint ?? this.fingerprint,
      realityPassword: realityPassword ?? this.realityPassword,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      path: path ?? this.path,
      host: host ?? this.host,
      serviceName: serviceName ?? this.serviceName,
      grpcMode: grpcMode ?? this.grpcMode,
      alpn: alpn ?? this.alpn,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      sourceLink: sourceLink ?? this.sourceLink,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'port': port,
        'userId': userId,
        'encryption': encryption,
        'flow': flow,
        'security': security,
        'transport': transport,
        'serverName': serverName,
        'fingerprint': fingerprint,
        'realityPassword': realityPassword,
        'shortId': shortId,
        'spiderX': spiderX,
        'path': path,
        'host': host,
        'serviceName': serviceName,
        'grpcMode': grpcMode,
        'alpn': alpn,
        'allowInsecure': allowInsecure,
        'sourceLink': sourceLink,
        'latencyMs': latencyMs,
      };

  factory TunnelProfile.fromJson(Map<String, Object?> json) {
    String stringValue(String key, [String fallback = '']) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    int intValue(String key, [int fallback = 0]) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    bool boolValue(String key, [bool fallback = false]) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final id = stringValue('id').trim();
    final address = stringValue('address').trim();
    final userId = stringValue('userId').trim();
    final port = intValue('port');
    if (id.isEmpty || address.isEmpty || userId.isEmpty) {
      throw const FormatException('Профиль содержит пустые обязательные поля');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Некорректный порт профиля');
    }

    final rawAlpn = json['alpn'];
    final alpn = rawAlpn is List
        ? rawAlpn.whereType<String>().toList(growable: false)
        : const <String>[];
    final latency = json['latencyMs'];

    return TunnelProfile(
      id: id,
      name: stringValue('name', address).trim().isEmpty
          ? address
          : stringValue('name', address).trim(),
      address: address,
      port: port,
      userId: userId,
      encryption: stringValue('encryption', 'none'),
      flow: stringValue('flow'),
      security: stringValue('security', 'none'),
      transport: stringValue('transport', 'raw'),
      serverName: stringValue('serverName'),
      fingerprint: stringValue('fingerprint', 'chrome'),
      realityPassword: stringValue('realityPassword'),
      shortId: stringValue('shortId'),
      spiderX: stringValue('spiderX'),
      path: stringValue('path'),
      host: stringValue('host'),
      serviceName: stringValue('serviceName'),
      grpcMode: stringValue('grpcMode'),
      alpn: alpn,
      allowInsecure: boolValue('allowInsecure'),
      sourceLink: stringValue('sourceLink'),
      latencyMs: latency is num ? latency.toInt() : null,
    );
  }
}

class TrafficStats {
  const TrafficStats({
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.duration = Duration.zero,
  });

  final int downloadBytes;
  final int uploadBytes;
  final Duration duration;
}

class TunnelSnapshot {
  const TunnelSnapshot({
    required this.status,
    required this.stats,
    this.mode = ConnectionMode.vpnTun,
    this.profile,
    this.message,
    this.errorMessage,
  });

  final TunnelStatus status;
  final ConnectionMode mode;
  final TunnelProfile? profile;
  final TrafficStats stats;
  final String? message;
  final String? errorMessage;

  bool get isBusy =>
      status == TunnelStatus.connecting || status == TunnelStatus.disconnecting;

  bool get isConnected => status == TunnelStatus.connected;

  TunnelSnapshot copyWith({
    TunnelStatus? status,
    ConnectionMode? mode,
    TunnelProfile? profile,
    bool clearProfile = false,
    TrafficStats? stats,
    String? message,
    bool clearMessage = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TunnelSnapshot(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      profile: clearProfile ? null : (profile ?? this.profile),
      stats: stats ?? this.stats,
      message: clearMessage ? null : (message ?? this.message),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
