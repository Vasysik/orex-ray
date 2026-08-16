import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

typedef LocalProxyTlsHandshaker = Future<void> Function(
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
/// balancer decision, and the currently selected outbound. HTTPS endpoints
/// complete a TLS handshake after the proxy CONNECT acknowledgement, so a
/// local HTTP-inbound acknowledgement alone can never become a false success.
/// Callers use it only for explicit lifecycle events or a manual refresh; it
/// is never a periodic background probe.
class TunnelRouteLatencyProbe {
  TunnelRouteLatencyProbe({
    this.timeout = const Duration(seconds: 6),
    Uri? probeUri,
    LocalProxyHttpRequester? requester,
    LocalProxyTlsHandshaker? tlsHandshaker,
    LocalProxyHttpRequester? httpsHeaderRequester,
  })  : probeUri = probeUri ?? defaultProbeUri,
        _requester = requester,
        _tlsHandshaker =
            tlsHandshaker ?? _completeTlsHandshakeThroughLocalProxy,
        _httpsHeaderRequester =
            httpsHeaderRequester ?? _requestResponseHeaderThroughLocalProxy;

  static final Uri defaultProbeUri =
      Uri.parse('https://cloudflare.com/cdn-cgi/trace');

  final Duration timeout;
  final Uri probeUri;
  final LocalProxyHttpRequester? _requester;
  final LocalProxyTlsHandshaker _tlsHandshaker;
  final LocalProxyHttpRequester _httpsHeaderRequester;

  Future<LatencyProbeResult> measure({
    required int httpPort,
    Uri? probeUri,
  }) async {
    final stopwatch = Stopwatch()..start();
    final activeProbeUri = probeUri ?? this.probeUri;
    try {
      await (_requester ?? _requestThroughLocalProxy)(
        httpPort,
        activeProbeUri,
        timeout: timeout,
      ).timeout(timeout);
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

  Future<void> _requestThroughLocalProxy(
    int httpPort,
    Uri probeUri, {
    required Duration timeout,
  }) async {
    if (probeUri.scheme == 'https') {
      try {
        await _tlsHandshaker(
          httpPort,
          probeUri,
          timeout: timeout,
        );
      } on TimeoutException {
        // The outer measurement timeout is a single budget. Retrying after a
        // full TLS timeout would turn one manual check into two long waits.
        rethrow;
      } on _TlsUpgradeException {
        // Some platform TLS stacks cannot upgrade a raw Socket after CONNECT.
        // HttpClient owns its CONNECT/TLS state machine and waits for the
        // remote response header, never treating Xray's local CONNECT 200 as
        // a successful route measurement.
        await _httpsHeaderRequester(
          httpPort,
          probeUri,
          timeout: timeout,
        );
      } on TlsException {
        // Allows a platform-specific/injected TLS implementation to signal
        // the same safe fallback without broadening this to CONNECT parsing
        // or local socket failures.
        await _httpsHeaderRequester(
          httpPort,
          probeUri,
          timeout: timeout,
        );
      }
      return;
    }

    await _requestResponseHeaderThroughLocalProxy(
      httpPort,
      probeUri,
      timeout: timeout,
    );
  }

  static Future<void> _requestResponseHeaderThroughLocalProxy(
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
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Route probe returned HTTP ${response.statusCode}');
      }
    } finally {
      // A first response header proves the selected route reached the probe.
      // Do not drain an arbitrary custom endpoint body: this probe measures
      // latency, not content size, and should use only one small request.
      client.close(force: true);
    }
  }

  /// Xray's HTTP inbound acknowledges CONNECT before it has dispatched the
  /// remote connection. Waiting only for that `200` measures localhost. A
  /// completed TLS handshake sends bytes through the selected Xray outbound
  /// and receives the configured public host's certificate, proving the
  /// remote path without adding an HTTP request/response round trip.
  static Future<void> _completeTlsHandshakeThroughLocalProxy(
    int httpPort,
    Uri probeUri, {
    required Duration timeout,
  }) async {
    Socket? socket;
    SecureSocket? secureSocket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        httpPort,
        timeout: timeout,
      );
      final port = probeUri.hasPort ? probeUri.port : 443;
      final authority = _authority(probeUri.host, port);
      socket.write(
        'CONNECT $authority HTTP/1.1\r\n'
        'Host: $authority\r\n'
        'Proxy-Connection: keep-alive\r\n'
        '\r\n',
      );
      await socket.flush();
      await _readConnectResponse(socket);

      // `_readConnectResponse` pauses its subscription before this call. The
      // Dart SDK transfers that subscription to SecureSocket, preserving the
      // unread transport stream for the TLS handshake.
      try {
        secureSocket = await SecureSocket.secure(
          socket,
          host: probeUri.host,
          supportedProtocols: const ['http/1.1'],
        );
      } on TimeoutException {
        rethrow;
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(_TlsUpgradeException(error), stackTrace);
      }
      socket = null;
    } finally {
      secureSocket?.destroy();
      socket?.destroy();
    }
  }

  static Future<void> _readConnectResponse(Socket socket) {
    final response = Completer<void>();
    final bytes = BytesBuilder(copy: false);
    late final StreamSubscription<Uint8List> subscription;

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!response.isCompleted) {
        response.completeError(error, stackTrace);
      }
    }

    subscription = socket.listen(
      (chunk) {
        if (response.isCompleted) return;
        bytes.add(chunk);
        final value = bytes.toBytes();
        final headerEnd = _headerEnd(value);
        if (headerEnd < 0) {
          if (value.length > 16 * 1024) {
            subscription.pause();
            fail(HttpException('Proxy CONNECT response is too large'));
          }
          return;
        }

        // No TLS bytes can legitimately precede the client hello. Rejecting
        // surplus bytes is safer than dropping them before SecureSocket takes
        // ownership of the paused subscription.
        if (value.length != headerEnd + 4) {
          subscription.pause();
          fail(HttpException('Unexpected bytes after proxy CONNECT'));
          return;
        }

        final header = String.fromCharCodes(value.sublist(0, headerEnd));
        final firstLine = header.split('\r\n').first;
        if (!RegExp(r'^HTTP/1\.[01] 200(?: |$)').hasMatch(firstLine)) {
          subscription.pause();
          fail(HttpException('Proxy CONNECT failed: $firstLine'));
          return;
        }
        // SecureSocket.secure explicitly requires an existing subscription to
        // be paused before it takes over the socket.
        subscription.pause();
        response.complete();
      },
      onError: fail,
      onDone: () {
        if (!response.isCompleted) {
          fail(const SocketException('Proxy closed before CONNECT response'));
        }
      },
      cancelOnError: true,
    );
    return response.future;
  }

  static int _headerEnd(Uint8List value) {
    for (var index = 0; index + 3 < value.length; index++) {
      if (value[index] == 13 &&
          value[index + 1] == 10 &&
          value[index + 2] == 13 &&
          value[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  static String _authority(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// Distinguishes a post-CONNECT TLS upgrade failure from an invalid or local
/// CONNECT response. Only the former can safely use the HttpClient fallback.
class _TlsUpgradeException implements Exception {
  const _TlsUpgradeException(this.cause);

  final Object cause;
}

bool isSocketTimeout(SocketException error) {
  final code = error.osError?.errorCode;
  if (code == 60 || code == 110 || code == 10060) return true;
  final message =
      '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  return message.contains('timed out') || message.contains('timeout');
}
