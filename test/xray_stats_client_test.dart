import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/platform/windows/xray_stats_client.dart';

void main() {
  test('encodes QueryStats pattern without reset flag', () {
    expect(
      XrayStatsClient.encodeQueryStatsRequest(pattern: 'inbound>>>orexray-'),
      [
        0x0a,
        18,
        ...utf8.encode('inbound>>>orexray-'),
      ],
    );
  });

  test('parses and sums only OrexRay traffic inbounds', () {
    final response = <int>[
      ..._field(1, _stat('inbound>>>orexray-http>>>traffic>>>downlink', 1200)),
      ..._field(1, _stat('inbound>>>orexray-socks>>>traffic>>>downlink', 300)),
      ..._field(1, _stat('inbound>>>orexray-http>>>traffic>>>uplink', 700)),
      ..._field(1, _stat('inbound>>>orexray-api>>>traffic>>>downlink', 9999)),
      ..._field(1, _stat('outbound>>>proxy>>>traffic>>>downlink', 7777)),
    ];

    final totals = XrayStatsClient.parseQueryStatsResponse(response);

    expect(totals.downloadBytes, 1500);
    expect(totals.uploadBytes, 700);
  });

  test('parses per-outbound totals for balancer members', () {
    final response = <int>[
      ..._field(1, _stat('outbound>>>proxy-0>>>traffic>>>downlink', 120)),
      ..._field(1, _stat('outbound>>>proxy-0>>>traffic>>>uplink', 30)),
      ..._field(1, _stat('outbound>>>proxy-1>>>traffic>>>downlink', 400)),
      ..._field(1, _stat('outbound>>>fallback-proxy>>>traffic>>>uplink', 50)),
      ..._field(1, _stat('outbound>>>direct>>>traffic>>>downlink', 9999)),
    ];

    final totals = XrayStatsClient.parseOutboundTotalsResponse(response);

    expect(totals['proxy-0'], 150);
    expect(totals['proxy-1'], 400);
    expect(totals['fallback-proxy'], 50);
    expect(totals.containsKey('direct'), isFalse);
  });

  test('supports multi-byte protobuf varints', () {
    final response = _field(
      1,
      _stat('inbound>>>orexray-tun>>>traffic>>>downlink', 1 << 35),
    );

    final totals = XrayStatsClient.parseQueryStatsResponse(response);

    expect(totals.downloadBytes, 1 << 35);
    expect(totals.uploadBytes, 0);
  });
}

List<int> _stat(String name, int value) => <int>[
      ..._field(1, utf8.encode(name)),
      0x10,
      ..._varint(value),
    ];

List<int> _field(int fieldNumber, List<int> payload) => <int>[
      (fieldNumber << 3) | 2,
      ..._varint(payload.length),
      ...payload,
    ];

List<int> _varint(int value) {
  final result = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    result.add(byte);
  } while (remaining != 0);
  return result;
}
