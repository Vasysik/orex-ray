import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  test('legacy stored latency migrates to a successful ping status', () {
    final profile = TunnelProfile.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'address': 'example.com',
      'port': 443,
      'userId': '11111111-1111-4111-8111-111111111111',
      'latencyMs': 82,
    });

    expect(profile.latencyMs, 82);
    expect(profile.pingStatus, PingStatus.success);
    expect(profile.toJson()['pingStatus'], 'success');
  });

  test('timeout and unavailable ping statuses round-trip without latency', () {
    for (final status in [PingStatus.timeout, PingStatus.unavailable]) {
      final profile = _profile(pingStatus: status);
      final restored = TunnelProfile.fromJson(profile.toJson());

      expect(restored.latencyMs, isNull);
      expect(restored.pingStatus, status);
    }
  });

  test('balancer reports a timeout when none of its members succeeded', () {
    final first = _profile(id: 'timeout', pingStatus: PingStatus.timeout);
    final second = _profile(
      id: 'unavailable',
      pingStatus: PingStatus.unavailable,
    );
    final target = TunnelTarget.balancer(
      const BalancerProfile(
        id: 'pool',
        name: 'Pool',
        memberIds: ['timeout', 'unavailable'],
      ),
      [first, second],
    );

    expect(target.latencyMs, isNull);
    expect(target.pingStatus, PingStatus.timeout);
  });

  test('latency probe reports a successful local TCP handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((socket) => socket.destroy());
    addTearDown(subscription.cancel);
    addTearDown(server.close);

    final result = await const LatencyProbe(
      timeout: Duration(seconds: 1),
    ).measure(_profile(port: server.port));

    expect(result.status, PingStatus.success);
    expect(result.latencyMs, greaterThanOrEqualTo(1));
  });

  test('latency probe classifies a timeout separately from an unavailable host',
      () async {
    final timeout = await const LatencyProbe(
      socketConnector: _timeoutConnector,
    ).measure(_profile());
    final unavailable = await const LatencyProbe(
      socketConnector: _unavailableConnector,
    ).measure(_profile());
    final socketTimeout = await const LatencyProbe(
      socketConnector: _socketTimeoutConnector,
    ).measure(_profile());

    expect(timeout.status, PingStatus.timeout);
    expect(timeout.latencyMs, isNull);
    expect(unavailable.status, PingStatus.unavailable);
    expect(unavailable.latencyMs, isNull);
    expect(socketTimeout.status, PingStatus.timeout);
  });
}

TunnelProfile _profile({
  String id = 'profile',
  int port = 443,
  PingStatus? pingStatus,
}) =>
    TunnelProfile(
      id: id,
      name: id,
      address: '127.0.0.1',
      port: port,
      userId: '11111111-1111-4111-8111-111111111111',
      pingStatus: pingStatus,
    );

Future<Socket> _timeoutConnector(
  String host,
  int port, {
  required Duration timeout,
}) =>
    Future<Socket>.error(TimeoutException('Connection timed out'));

Future<Socket> _unavailableConnector(
  String host,
  int port, {
  required Duration timeout,
}) =>
    Future<Socket>.error(SocketException('Connection refused'));

Future<Socket> _socketTimeoutConnector(
  String host,
  int port, {
  required Duration timeout,
}) =>
    Future<Socket>.error(
      SocketException(
        'Connection timed out',
        osError: OSError('Connection timed out', 10060),
      ),
    );
