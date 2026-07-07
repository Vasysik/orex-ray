import 'package:flutter/services.dart';

class WindowsTunRouteStatus {
  const WindowsTunRouteStatus({
    required this.ipv4Interface,
    required this.ipv6Interface,
    required this.ipv4Captured,
    required this.ipv6Captured,
  });

  factory WindowsTunRouteStatus.fromMap(Map<Object?, Object?> map) {
    return WindowsTunRouteStatus(
      ipv4Interface: (map['ipv4Interface'] as String?)?.trim() ?? '',
      ipv6Interface: (map['ipv6Interface'] as String?)?.trim() ?? '',
      ipv4Captured: map['ipv4Captured'] == true,
      ipv6Captured: map['ipv6Captured'] == true,
    );
  }

  final String ipv4Interface;
  final String ipv6Interface;
  final bool ipv4Captured;
  final bool ipv6Captured;

  bool get fullyCaptured =>
      ipv4Captured && (ipv6Interface.isEmpty || ipv6Captured);

  String get summary {
    final ipv4 = ipv4Interface.isEmpty ? 'unknown' : ipv4Interface;
    final ipv6 = ipv6Interface.isEmpty ? 'unavailable' : ipv6Interface;
    return 'IPv4 best route → $ipv4 · IPv6 best route → $ipv6';
  }
}

class WindowsNetworkController {
  const WindowsNetworkController._();

  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');

  static Future<String?> bestOutboundInterface() async {
    final value = await _channel.invokeMethod<String>('getBestOutboundInterface');
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Future<WindowsTunRouteStatus> tunRouteStatus() async {
    final value = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getTunRouteStatus',
    );
    return WindowsTunRouteStatus.fromMap(value ?? const <Object?, Object?>{});
  }
}
