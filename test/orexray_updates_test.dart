import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/update/orexray_updates.dart';

void main() {
  test('versions compare numerically, not lexicographically', () {
    expect(OrexRayRelease.compareVersions('0.7.0+12', '0.6.8+11'), greaterThan(0));
    expect(OrexRayRelease.compareVersions('0.7.0+12', '0.7.0+12'), 0);
    expect(OrexRayRelease.compareVersions('0.7.0+2', '0.7.0+12'), lessThan(0));
    expect(OrexRayRelease.compareVersions('bad', '0.7.0+12'), isNull);
    expect(OrexRayRelease.shouldOffer('0.7.0+12', '0.7.0+12'), isFalse);
    expect(OrexRayRelease.shouldOffer('0.7.0+12', '0.7.0+12', allowSame: true), isTrue);
    expect(OrexRayRelease.shouldOffer('0.6.8+11', '0.7.0+12', allowSame: true), isFalse);
  });

  test('parses official GitHub asset names only with checksums', () {
    Map<String, dynamic> fixture(String asset, {String host = 'github.com'}) => {
      'tag_name': '0.7.0+12',
      'draft': false,
      'body': 'Описание релиза',
      'assets': [
        {'name': asset, 'size': 42000,
          'browser_download_url': 'https://$host/Vasysik/orex-ray/releases/download/0.7.0%2B12/$asset'},
        {'name': 'SHA256SUMS.txt', 'size': 300,
          'browser_download_url': 'https://github.com/Vasysik/orex-ray/releases/download/0.7.0%2B12/SHA256SUMS.txt'},
      ],
    };
    const name = 'OrexRay-0.7.0+12-arm64-v8a.apk';
    final r = OrexRayRelease.parse(fixture(name), 'arm64-v8a.apk');
    expect(r?.tag, '0.7.0+12');
    expect(r?.assetName, name);
    expect(OrexRayRelease.parse(fixture(name, host: 'evil.example'), 'arm64-v8a.apk'), isNull);
    expect(OrexRayRelease.parse(fixture('wrong.apk'), 'arm64-v8a.apk'), isNull);
  });
}
