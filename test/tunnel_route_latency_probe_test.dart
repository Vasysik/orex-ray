import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  test('route probe defaults to Cloudflare and accepts a URI per check',
      () async {
    final configuredUri = Uri.parse('https://probe.example.com/check');
    Uri? requestedUri;
    final probe = TunnelRouteLatencyProbe(
      requester: (_, uri, {required timeout}) async {
        requestedUri = uri;
      },
    );

    await probe.measure(httpPort: 20809, probeUri: configuredUri);

    expect(
      TunnelRouteLatencyProbe().probeUri.toString(),
      'https://cloudflare.com/cdn-cgi/trace',
    );
    expect(requestedUri, configuredUri);
  });

  test('route probe reports a successful local-proxy request', () async {
    final result = await TunnelRouteLatencyProbe(
      requester: (_, __, {required timeout}) async {},
    ).measure(httpPort: 20809);

    expect(result.status, PingStatus.success);
    expect(result.latencyMs, isNotNull);
  });

  test('route probe reports a timeout separately from unavailability',
      () async {
    final result = await TunnelRouteLatencyProbe(
      requester: (_, __, {required timeout}) {
        throw TimeoutException('proxy request timed out');
      },
    ).measure(httpPort: 20809);

    expect(result.status, PingStatus.timeout);
    expect(result.latencyMs, isNull);
  });

  test('route probe waits for a 2xx response header without downloading body',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? requestLine;
    final served = server.first.then((socket) async {
      requestLine = await utf8.decoder
          .bind(socket.cast<List<int>>())
          .transform(const LineSplitter())
          .first;
      socket.add(
        utf8.encode(
          'HTTP/1.1 204 No Content\r\n'
          'Content-Length: 999999\r\n'
          '\r\n',
        ),
      );
      await socket.flush();
      socket.destroy();
    });

    final result = await TunnelRouteLatencyProbe(
      probeUri: Uri.parse('http://probe.example.com/health'),
    ).measure(httpPort: server.port);
    await served;

    expect(requestLine, 'GET http://probe.example.com/health HTTP/1.1');
    expect(result.status, PingStatus.success);
  });

  test('HTTPS route probe does not count a local CONNECT reply as success',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? requestLine;
    final served = server.first.then((socket) async {
      requestLine = await utf8.decoder
          .bind(socket.cast<List<int>>())
          .transform(const LineSplitter())
          .first;
      socket.add(
        utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
      );
      await socket.flush();
      // A proxy's local CONNECT acknowledgement alone is not evidence that
      // the remote route is usable. Closing before TLS must not become 1 ms.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.destroy();
    });

    final result = await TunnelRouteLatencyProbe(
      timeout: const Duration(seconds: 1),
      probeUri: Uri.parse('https://probe.example.com/health'),
      httpsHeaderRequester: (_, __, {required timeout}) async {
        throw const SocketException('remote route did not return a header');
      },
    ).measure(httpPort: server.port);
    await served;

    expect(requestLine, 'CONNECT probe.example.com:443 HTTP/1.1');
    expect(result.status, PingStatus.unavailable);
    expect(result.latencyMs, isNull);
  });

  test('HTTPS route probe reaches TLS after an Xray-style CONNECT response',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? requestLine;
    List<int>? tlsClientHello;
    final served = server.first.then((socket) async {
      final requestBytes = BytesBuilder(copy: false);
      var replied = false;
      await for (final chunk in socket) {
        if (!replied) {
          requestBytes.add(chunk);
          final request = latin1.decode(requestBytes.toBytes());
          if (!request.contains('\r\n\r\n')) continue;
          requestLine = request.split('\r\n').first;
          replied = true;
          socket.add(
            utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
          );
          await socket.flush();
          continue;
        }

        tlsClientHello = chunk;
        socket.destroy();
        return;
      }
    });
    var fallbackCalls = 0;

    final result = await TunnelRouteLatencyProbe(
      timeout: const Duration(seconds: 1),
      probeUri: Uri.parse('https://probe.example.com/health'),
      httpsHeaderRequester: (_, __, {required timeout}) async {
        fallbackCalls++;
      },
    ).measure(httpPort: server.port);
    await served.timeout(const Duration(seconds: 1));

    expect(requestLine, 'CONNECT probe.example.com:443 HTTP/1.1');
    expect(tlsClientHello, isNotNull);
    expect(tlsClientHello!.first, 22); // TLS handshake record.
    expect(fallbackCalls, 1);
    expect(result.status, PingStatus.success);
  });

  test('HTTPS route probe falls back to a remote response header on TLS error',
      () async {
    var tlsCalls = 0;
    var headerCalls = 0;
    final result = await TunnelRouteLatencyProbe(
      tlsHandshaker: (_, __, {required timeout}) async {
        tlsCalls++;
        throw const HandshakeException('raw TLS upgrade unavailable');
      },
      httpsHeaderRequester: (_, __, {required timeout}) async {
        headerCalls++;
      },
    ).measure(
      httpPort: 20809,
      probeUri: Uri.parse('https://probe.example.com/health'),
    );

    expect(tlsCalls, 1);
    expect(headerCalls, 1);
    expect(result.status, PingStatus.success);
  });

  test('HTTPS route probe does not retry after a TLS timeout', () async {
    var headerCalls = 0;
    final result = await TunnelRouteLatencyProbe(
      tlsHandshaker: (_, __, {required timeout}) async {
        throw TimeoutException('TLS handshake timed out');
      },
      httpsHeaderRequester: (_, __, {required timeout}) async {
        headerCalls++;
      },
    ).measure(
      httpPort: 20809,
      probeUri: Uri.parse('https://probe.example.com/health'),
    );

    expect(headerCalls, 0);
    expect(result.status, PingStatus.timeout);
  });

  test('route probe rejects a failed HTTP response', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final served = server.first.then((socket) async {
      socket.add(utf8.encode('HTTP/1.1 502 Bad Gateway\r\n\r\n'));
      await socket.flush();
      socket.destroy();
    });

    final result = await TunnelRouteLatencyProbe(
      probeUri: Uri.parse('http://probe.example.com/health'),
    ).measure(httpPort: server.port);
    await served;

    expect(result.status, PingStatus.unavailable);
  });

  test('route probe does not follow redirects from a custom endpoint',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final served = server.first.then((socket) async {
      socket.add(
        utf8.encode(
          'HTTP/1.1 302 Found\r\n'
          'Location: http://127.0.0.1/private\r\n'
          '\r\n',
        ),
      );
      await socket.flush();
      socket.destroy();
    });

    final result = await TunnelRouteLatencyProbe(
      probeUri: Uri.parse('http://probe.example.com/health'),
    ).measure(httpPort: server.port);
    await served;

    expect(result.status, PingStatus.unavailable);
  });
}
