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
        ConnectionMode.vpnTun =>
          'Весь трафик устройства через защищённый туннель',
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

enum BalancerStrategy {
  random,
  roundRobin,
  leastPing;

  String get storageValue => switch (this) {
        BalancerStrategy.random => 'random',
        BalancerStrategy.roundRobin => 'roundRobin',
        BalancerStrategy.leastPing => 'leastPing',
      };

  String get title => switch (this) {
        BalancerStrategy.random => 'Случайный',
        BalancerStrategy.roundRobin => 'По очереди',
        BalancerStrategy.leastPing => 'Минимальный ping',
      };

  String get description => switch (this) {
        BalancerStrategy.random =>
          'Каждое новое соединение получает случайный доступный сервер',
        BalancerStrategy.roundRobin => 'Серверы используются по кругу',
        BalancerStrategy.leastPing =>
          'Xray выбирает сервер с минимальной измеренной задержкой',
      };

  static BalancerStrategy fromStorageValue(String? value) => switch (value) {
        'roundRobin' => BalancerStrategy.roundRobin,
        'leastPing' => BalancerStrategy.leastPing,
        _ => BalancerStrategy.random,
      };
}

/// Result of the most recent manual reachability check for a profile.
///
/// `unknown` is the initial state. A successful TCP handshake has a latency
/// value, while `timeout` and `unavailable` deliberately do not: treating both
/// failures as a missing number used to make their UI indistinguishable.
enum PingStatus {
  unknown,
  success,
  timeout,
  unavailable;

  String get storageValue => name;

  static PingStatus? fromStorageValue(String? value) => switch (value) {
        'unknown' => PingStatus.unknown,
        'success' => PingStatus.success,
        'timeout' => PingStatus.timeout,
        'unavailable' => PingStatus.unavailable,
        _ => null,
      };
}

/// The outbound protocol used by a saved connection profile.
///
/// Old saved entries did not carry this field, so an absent value is always
/// treated as VLESS. This keeps existing profiles readable without migration.
enum OutboundProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  socks,
  http;

  String get storageValue => switch (this) {
        OutboundProtocol.vless => 'vless',
        OutboundProtocol.vmess => 'vmess',
        OutboundProtocol.trojan => 'trojan',
        OutboundProtocol.shadowsocks => 'shadowsocks',
        OutboundProtocol.socks => 'socks',
        OutboundProtocol.http => 'http',
      };

  String get title => switch (this) {
        OutboundProtocol.vless => 'VLESS',
        OutboundProtocol.vmess => 'VMess',
        OutboundProtocol.trojan => 'Trojan',
        OutboundProtocol.shadowsocks => 'Shadowsocks',
        OutboundProtocol.socks => 'SOCKS5',
        OutboundProtocol.http => 'HTTP proxy',
      };

  static OutboundProtocol? fromStorageValue(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'vless' => OutboundProtocol.vless,
        'vmess' => OutboundProtocol.vmess,
        'trojan' => OutboundProtocol.trojan,
        'shadowsocks' || 'ss' => OutboundProtocol.shadowsocks,
        'socks' || 'socks5' => OutboundProtocol.socks,
        'http' || 'https' => OutboundProtocol.http,
        _ => null,
      };
}

class TunnelProfile {
  const TunnelProfile({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.userId,
    this.outboundProtocol = OutboundProtocol.vless,
    this.password = '',
    this.vmessSecurity = 'auto',
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
    PingStatus? pingStatus,
  }) : pingStatus = pingStatus ??
            (latencyMs == null ? PingStatus.unknown : PingStatus.success);

  final String id;
  final String name;
  final String address;
  final int port;

  /// VLESS/VMess UUID or SOCKS/HTTP username.
  final String userId;

  /// Trojan/Shadowsocks password or SOCKS/HTTP password.
  final String password;
  final OutboundProtocol outboundProtocol;

  /// VMess payload cipher (`auto` by default), independent from TLS/REALITY.
  final String vmessSecurity;
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
  final PingStatus pingStatus;

  String get endpoint => '$address:$port';

  String get protocol {
    if (outboundProtocol == OutboundProtocol.shadowsocks) {
      return 'Shadowsocks · ${encryption.toUpperCase()}';
    }
    if (outboundProtocol == OutboundProtocol.socks) return 'SOCKS5';
    if (outboundProtocol == OutboundProtocol.http) {
      return security == 'tls' ? 'HTTPS proxy' : 'HTTP proxy';
    }
    final securityLabel = switch (security) {
      'reality' => 'REALITY',
      'tls' => 'TLS',
      _ => 'NONE',
    };
    return '${outboundProtocol.title} · $securityLabel';
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
    String? password,
    OutboundProtocol? outboundProtocol,
    String? vmessSecurity,
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
    PingStatus? pingStatus,
    bool clearLatency = false,
  }) {
    final nextLatency = clearLatency ? null : (latencyMs ?? this.latencyMs);
    final nextPingStatus = pingStatus ??
        (clearLatency
            ? PingStatus.unknown
            : latencyMs != null
                ? PingStatus.success
                : this.pingStatus);
    return TunnelProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      userId: userId ?? this.userId,
      password: password ?? this.password,
      outboundProtocol: outboundProtocol ?? this.outboundProtocol,
      vmessSecurity: vmessSecurity ?? this.vmessSecurity,
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
      latencyMs: nextLatency,
      pingStatus: nextPingStatus,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'port': port,
        'userId': userId,
        if (outboundProtocol != OutboundProtocol.vless)
          'outboundProtocol': outboundProtocol.storageValue,
        if (password.isNotEmpty) 'password': password,
        if (outboundProtocol == OutboundProtocol.vmess &&
            vmessSecurity != 'auto')
          'vmessSecurity': vmessSecurity,
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
        'pingStatus': pingStatus.storageValue,
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
    final storedOutboundProtocol = stringValue('outboundProtocol').trim();
    final outboundProtocol = storedOutboundProtocol.isEmpty
        ? OutboundProtocol.vless
        : OutboundProtocol.fromStorageValue(storedOutboundProtocol);
    if (outboundProtocol == null) {
      throw const FormatException('Неподдерживаемый протокол профиля');
    }
    final password = stringValue('password');
    final port = intValue('port');
    final needsUserId = outboundProtocol == OutboundProtocol.vless ||
        outboundProtocol == OutboundProtocol.vmess;
    final needsPassword = outboundProtocol == OutboundProtocol.trojan ||
        outboundProtocol == OutboundProtocol.shadowsocks;
    if (id.isEmpty ||
        address.isEmpty ||
        (needsUserId && userId.isEmpty) ||
        (needsPassword && password.isEmpty)) {
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
    final parsedLatency =
        latency is num && latency >= 0 ? latency.toInt() : null;
    final storedPingStatus = PingStatus.fromStorageValue(
      json['pingStatus'] as String?,
    );
    final pingStatus = storedPingStatus == PingStatus.success &&
            parsedLatency == null
        ? PingStatus.unknown
        : storedPingStatus ??
            (parsedLatency == null ? PingStatus.unknown : PingStatus.success);

    return TunnelProfile(
      id: id,
      name: stringValue('name', address).trim().isEmpty
          ? address
          : stringValue('name', address).trim(),
      address: address,
      port: port,
      userId: userId,
      password: password,
      outboundProtocol: outboundProtocol,
      vmessSecurity: stringValue('vmessSecurity', 'auto'),
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
      latencyMs: pingStatus == PingStatus.success ? parsedLatency : null,
      pingStatus: pingStatus,
    );
  }
}

class BalancerProfile {
  const BalancerProfile({
    required this.id,
    required this.name,
    required this.memberIds,
    this.strategy = BalancerStrategy.leastPing,
    this.probeUrl = 'https://www.gstatic.com/generate_204',
    this.probeIntervalSeconds = 30,
    this.fallbackTarget,
  });

  static const fallbackDirect = 'direct';
  static const fallbackBlock = 'block';
  static const fallbackProfilePrefix = 'profile:';

  final String id;
  final String name;
  final List<String> memberIds;
  final BalancerStrategy strategy;
  final String probeUrl;
  final int probeIntervalSeconds;

  /// App-level fallback selector. Values are `direct`, `block`, or
  /// `profile:<profile-id>`. It is translated to Xray's official
  /// `BalancerObject.fallbackTag` when the config is built.
  final String? fallbackTarget;

  String? get fallbackProfileId {
    final value = fallbackTarget;
    if (value == null || !value.startsWith(fallbackProfilePrefix)) return null;
    final id = value.substring(fallbackProfilePrefix.length).trim();
    return id.isEmpty ? null : id;
  }

  static String fallbackProfile(String profileId) =>
      '$fallbackProfilePrefix$profileId';

  BalancerProfile copyWith({
    String? id,
    String? name,
    List<String>? memberIds,
    BalancerStrategy? strategy,
    String? probeUrl,
    int? probeIntervalSeconds,
    String? fallbackTarget,
    bool clearFallback = false,
  }) {
    return BalancerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      strategy: strategy ?? this.strategy,
      probeUrl: probeUrl ?? this.probeUrl,
      probeIntervalSeconds: probeIntervalSeconds ?? this.probeIntervalSeconds,
      fallbackTarget:
          clearFallback ? null : (fallbackTarget ?? this.fallbackTarget),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'strategy': strategy.storageValue,
        'probeUrl': probeUrl,
        'probeIntervalSeconds': probeIntervalSeconds,
        if (fallbackTarget != null) 'fallbackTarget': fallbackTarget,
      };

  factory BalancerProfile.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    final rawMembers = json['memberIds'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final interval = (json['probeIntervalSeconds'] as num?)?.toInt() ?? 30;
    if (id.isEmpty || name.isEmpty || members.length < 2) {
      throw const FormatException('Некорректный балансировщик');
    }
    final fallbackTarget = (json['fallbackTarget'] as String?)?.trim();
    return BalancerProfile(
      id: id,
      name: name,
      memberIds: members,
      strategy: BalancerStrategy.fromStorageValue(json['strategy'] as String?),
      probeUrl: (json['probeUrl'] as String? ??
              'https://www.gstatic.com/generate_204')
          .trim(),
      probeIntervalSeconds: interval.clamp(30, 3600).toInt(),
      fallbackTarget: fallbackTarget == null || fallbackTarget.isEmpty
          ? null
          : fallbackTarget,
    );
  }
}

class TunnelTarget {
  const TunnelTarget._({
    required this.id,
    required this.name,
    required this.profiles,
    this.balancer,
    this.fallbackProfile,
  });

  factory TunnelTarget.single(TunnelProfile profile) => TunnelTarget._(
        id: profile.id,
        name: profile.name,
        profiles: [profile],
      );

  factory TunnelTarget.balancer(
    BalancerProfile balancer,
    List<TunnelProfile> profiles, {
    TunnelProfile? fallbackProfile,
  }) =>
      TunnelTarget._(
        id: balancer.id,
        name: balancer.name,
        profiles: List.unmodifiable(profiles),
        balancer: balancer,
        fallbackProfile: fallbackProfile,
      );

  final String id;
  final String name;
  final List<TunnelProfile> profiles;
  final BalancerProfile? balancer;
  final TunnelProfile? fallbackProfile;

  bool get isBalancer => balancer != null;
  TunnelProfile get primaryProfile => profiles.first;
  String get endpoint =>
      isBalancer ? '${profiles.length} серверов' : primaryProfile.endpoint;
  String get protocol => isBalancer
      ? 'Балансировщик · ${balancer!.strategy.title}'
      : primaryProfile.protocol;
  String get transportLabel =>
      isBalancer ? balancer!.strategy.title : primaryProfile.transportLabel;
  int? get latencyMs {
    final values = profiles
        .where((item) => item.pingStatus == PingStatus.success)
        .map((item) => item.latencyMs)
        .whereType<int>()
        .toList();
    if (values.isEmpty) return null;
    values.sort();
    return values.first;
  }

  PingStatus get pingStatus {
    if (!isBalancer) return primaryProfile.pingStatus;
    if (latencyMs != null) return PingStatus.success;
    if (profiles.any((item) => item.pingStatus == PingStatus.timeout)) {
      return PingStatus.timeout;
    }
    if (profiles.any((item) => item.pingStatus == PingStatus.unavailable)) {
      return PingStatus.unavailable;
    }
    return PingStatus.unknown;
  }
}

class TrafficStats {
  const TrafficStats({
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.downloadBytesPerSecond = 0,
    this.uploadBytesPerSecond = 0,
    this.duration = Duration.zero,
  });

  final int downloadBytes;
  final int uploadBytes;
  final int downloadBytesPerSecond;
  final int uploadBytesPerSecond;
  final Duration duration;

  TrafficStats copyWithDuration(Duration value) => TrafficStats(
        downloadBytes: downloadBytes,
        uploadBytes: uploadBytes,
        downloadBytesPerSecond: downloadBytesPerSecond,
        uploadBytesPerSecond: uploadBytesPerSecond,
        duration: value,
      );
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
  final TunnelTarget? profile;
  final TrafficStats stats;
  final String? message;
  final String? errorMessage;

  bool get isBusy =>
      status == TunnelStatus.connecting || status == TunnelStatus.disconnecting;

  bool get isConnected => status == TunnelStatus.connected;

  TunnelSnapshot copyWith({
    TunnelStatus? status,
    ConnectionMode? mode,
    TunnelTarget? profile,
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
