import 'dart:async';
import 'dart:io';

import '../tunnel/tunnel_models.dart';

typedef LatencySocketConnector = Future<Socket> Function(
  String host,
  int port, {
  required Duration timeout,
});

typedef LocalProxyHttpRequester = Future<void> Function(
  int httpPort,
  Uri probeUri, {
  required Duration timeout,
});

class LatencyProbeResult {
  const LatencyProbeResult.success(this.latencyMs)
      : assert(latencyMs != null && latencyMs > 0),
        status = PingStatus.success;

  const LatencyProbeResult.timeout()
      : latencyMs = null,
        status = PingStatus.timeout;

  const LatencyProbeResult.unavailable()
      : latencyMs = null,
        status = PingStatus.unavailable;

  final int? latencyMs;
  final PingStatus status;
}

class LatencyProbe {
  const LatencyProbe({
    this.timeout = const Duration(seconds: 4),
    LatencySocketConnector? socketConnector,
  }) : _socketConnector = socketConnector;

  final Duration timeout;
  final LatencySocketConnector? _socketConnector;

  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await (_socketConnector ?? _connect)(
        profile.address,
        profile.port,
        timeout: timeout,
      );
      stopwatch.stop();
      return LatencyProbeResult.success(
        stopwatch.elapsedMilliseconds.clamp(1, 60000).toInt(),
      );
    } on TimeoutException {
      return const LatencyProbeResult.timeout();
    } on SocketException catch (error) {
      return isSocketTimeout(error)
          ? const LatencyProbeResult.timeout()
          : const LatencyProbeResult.unavailable();
    } on Object {
      return const LatencyProbeResult.unavailable();
    } finally {
      socket?.destroy();
    }
  }

  static Future<Socket> _connect(
    String host,
    int port, {
    required Duration timeout,
  }) =>
      Socket.connect(host, port, timeout: timeout);
}

/// Measures an already active Xray route through its local HTTP proxy.
///
/// Unlike [LatencyProbe], this is an end-to-end check: it includes a cascade,
/// balancer decision, and the currently selected outbound. It is intentionally
/// used only after a manual refresh, never as a background probe.
class TunnelRouteLatencyProbe {
  TunnelRouteLatencyProbe({
    this.timeout = const Duration(seconds: 6),
    Uri? probeUri,
    LocalProxyHttpRequester? requester,
  })  : probeUri = probeUri ?? Uri.https('www.gstatic.com', '/generate_204'),
        _requester = requester;

  final Duration timeout;
  final Uri probeUri;
  final LocalProxyHttpRequester? _requester;

  Future<LatencyProbeResult> measure({required int httpPort}) async {
    final stopwatch = Stopwatch()..start();
    try {
      await (_requester ?? _requestThroughLocalProxy)(
        httpPort,
        probeUri,
        timeout: timeout,
      );
      stopwatch.stop();
      return LatencyProbeResult.success(
        stopwatch.elapsedMilliseconds.clamp(1, 60000).toInt(),
      );
    } on TimeoutException {
      return const LatencyProbeResult.timeout();
    } on SocketException catch (error) {
      return isSocketTimeout(error)
          ? const LatencyProbeResult.timeout()
          : const LatencyProbeResult.unavailable();
    } on Object {
      return const LatencyProbeResult.unavailable();
    }
  }

  static Future<void> _requestThroughLocalProxy(
    int httpPort,
    Uri probeUri, {
    required Duration timeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout
      ..findProxy = (_) => 'PROXY 127.0.0.1:$httpPort';
    try {
      final request = await client.getUrl(probeUri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('Route probe returned HTTP ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }
}

bool isSocketTimeout(SocketException error) {
  final code = error.osError?.errorCode;
  if (code == 60 || code == 110 || code == 10060) return true;
  final message =
      '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  return message.contains('timed out') || message.contains('timeout');
}
