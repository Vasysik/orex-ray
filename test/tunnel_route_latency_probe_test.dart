import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
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
}
