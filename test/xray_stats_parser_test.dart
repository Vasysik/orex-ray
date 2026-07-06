import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/platform/windows/xray_stats_parser.dart';

void main() {
  test('sums Xray inbound traffic counters without counting outbounds', () {
    const response = '''
{
  "stat": [
    {"name":"inbound>>>orexray-socks>>>traffic>>>downlink","value":"1200"},
    {"name":"inbound>>>orexray-socks>>>traffic>>>uplink","value":"300"},
    {"name":"inbound>>>orexray-http>>>traffic>>>downlink","value":"800"},
    {"name":"inbound>>>orexray-http>>>traffic>>>uplink","value":"200"},
    {"name":"outbound>>>proxy>>>traffic>>>downlink","value":"999999"}
  ]
}
''';

    final totals = parseXrayInboundStats(response);

    expect(totals.downloadBytes, 2000);
    expect(totals.uploadBytes, 500);
  });

  test('accepts numeric counters and ignores malformed entries', () {
    const response = '''
{
  "stat": [
    {"name":"inbound>>>orexray-tun>>>traffic>>>downlink","value":42},
    {"name":"inbound>>>orexray-tun>>>traffic>>>uplink","value":"bad"},
    {"value":"100"}
  ]
}
''';

    final totals = parseXrayInboundStats(response);

    expect(totals.downloadBytes, 42);
    expect(totals.uploadBytes, 0);
  });
}
