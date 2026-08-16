import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/profiles/latency_probe.dart';
import '../../core/tunnel/tunnel_models.dart';

/// A direct TCP probe that asks the Windows runner to bind the socket to the
/// physical outbound adapter.
///
/// A normal Dart [Socket.connect] is correct when no TUN is active, but on a
/// Windows VPN it can be captured by OrexRay's Wintun default route. The
/// runner uses `IP_UNICAST_IF`/`IPV6_UNICAST_IF`, so it must never fall back to
/// an unbound Dart socket if the native capability is unavailable.
class WindowsDirectLatencyProbe extends LatencyProbe {
  WindowsDirectLatencyProbe({
    super.timeout = const Duration(seconds: 4),
    MethodChannel? channel,
  })  : _channel = channel ?? _defaultChannel,
        super(canMeasureWhileVpnActive: true);

  static const _defaultChannel = MethodChannel('ru.orex.ray/windows_lifecycle');

  final MethodChannel _channel;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('measureDirectLatency', <String, Object>{
        'host': profile.address,
        'port': profile.port,
        'timeoutMs': timeout.inMilliseconds,
      })
          // The native worker owns the actual TCP timeout. This small grace
          // period only protects against a lost platform reply; it does not
          // create an unsafe fallback path through Wintun.
          .timeout(timeout + const Duration(seconds: 1));
      if (raw is! Map) throw const LatencyMeasurementSkipped();

      final status = PingStatus.fromStorageValue(raw['status'] as String?);
      if (raw['status'] == 'skipped') {
        throw const LatencyMeasurementSkipped();
      }
      if (status == PingStatus.timeout) {
        return const LatencyProbeResult.timeout();
      }
      if (status != PingStatus.success) {
        return const LatencyProbeResult.unavailable();
      }

      final latency = raw['latencyMs'];
      if (latency is! num || latency <= 0) {
        throw const LatencyMeasurementSkipped();
      }
      return LatencyProbeResult.success(
        latency.toInt().clamp(1, 60000).toInt(),
      );
    } on TimeoutException {
      // This is the Dart-side grace timer, not a server timeout from the
      // native worker. Retain the saved value rather than inventing a result.
      throw const LatencyMeasurementSkipped();
    } on MissingPluginException {
      // An older runner cannot prove that it will bypass the TUN. Leave the
      // saved value untouched at the controller level rather than measuring a
      // recursive 1–4 ms socket.
      throw const LatencyMeasurementSkipped();
    } on PlatformException {
      throw const LatencyMeasurementSkipped();
    } on Object {
      throw const LatencyMeasurementSkipped();
    }
  }
}
