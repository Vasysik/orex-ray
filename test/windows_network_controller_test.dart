import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/platform/windows/windows_network_controller.dart';

void main() {
  test('TUN route status requires every available IP family to be captured', () {
    const dualStackPending = WindowsTunRouteStatus(
      ipv4Interface: 'OrexRay',
      ipv6Interface: 'Wi-Fi',
      ipv4Captured: true,
      ipv6Captured: false,
    );
    const ipv4Only = WindowsTunRouteStatus(
      ipv4Interface: 'OrexRay',
      ipv6Interface: '',
      ipv4Captured: true,
      ipv6Captured: false,
    );
    const dualStackReady = WindowsTunRouteStatus(
      ipv4Interface: 'OrexRay',
      ipv6Interface: 'OrexRay',
      ipv4Captured: true,
      ipv6Captured: true,
    );

    expect(dualStackPending.fullyCaptured, isFalse);
    expect(ipv4Only.fullyCaptured, isTrue);
    expect(dualStackReady.fullyCaptured, isTrue);
  });

  test('TUN route status decodes native diagnostics', () {
    final value = WindowsTunRouteStatus.fromMap(const {
      'ipv4Interface': ' OrexRay ',
      'ipv6Interface': 'Wi-Fi',
      'ipv4Captured': true,
      'ipv6Captured': false,
    });

    expect(value.ipv4Interface, 'OrexRay');
    expect(value.ipv6Interface, 'Wi-Fi');
    expect(value.summary, 'IPv4 → OrexRay ✓ · IPv6 → Wi-Fi ✗');
  });
}
