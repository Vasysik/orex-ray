import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/egress_identity.dart';

void main() {
  test('parses country and WARP state without retaining the exit IP', () {
    final identity = parseCloudflareTrace(
      'fl=29f\nip=203.0.113.10\nloc=NL\nwarp=on\n',
      checkedAt: DateTime(2026, 7, 7),
    );

    expect(identity, isNotNull);
    expect(identity!.countryCode, 'NL');
    expect(identity.flagEmoji, '🇳🇱');
    expect(identity.warp, isTrue);
    expect(identity.toJson().containsKey('ip'), isFalse);
  });
}
