import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/subscription_parser.dart';

void main() {
  const first =
      'vless://11111111-1111-4111-8111-111111111111@one.example:443'
      '?encryption=none&security=none&type=tcp#One';
  const second =
      'vless://22222222-2222-4222-8222-222222222222@two.example:443'
      '?encryption=none&security=none&type=tcp#Two';

  test('parses plain subscription and metadata', () {
    final result = const SubscriptionParser().parse('''
#profile-title: Test VPN
#profile-update-interval: 6
#subscription-userinfo: upload=1; download=2; total=10; expire=0
#support-url: https://support.example/help
#profile-web-page-url: https://panel.example/user
#announce: Maintenance tonight
happ://routing/onadd/ignored
$first
$second
''');

    expect(result.profiles.map((profile) => profile.name).toList(), ['One', 'Two']);
    expect(result.profileTitle, 'Test VPN');
    expect(result.updateIntervalHours, 6);
    expect(result.userInfo, contains('total=10'));
    expect(result.supportUrl, 'https://support.example/help');
    expect(result.webPageUrl, 'https://panel.example/user');
    expect(result.announce, 'Maintenance tonight');
    expect(result.skippedUnsupported, 1);
  });

  test('decodes base64 metadata values from subscription body', () {
    final userInfo = base64.encode(
      utf8.encode('upload=10; download=20; total=100; expire=2000000000'),
    );
    final support = base64.encode(utf8.encode('https://support.example/help'));
    final result = const SubscriptionParser().parse('''
#subscription-userinfo: base64:$userInfo
#support-url: base64:$support
$first
''');

    expect(result.userInfo, contains('total=100'));
    expect(result.supportUrl, 'https://support.example/help');
  });

  test('parses legacy base64 V2Ray subscription', () {
    final encoded = base64.encode(utf8.encode('$first\n$second\n'));
    final result = const SubscriptionParser().parse(encoded);

    expect(result.profiles, hasLength(2));
    expect(result.profiles.map((profile) => profile.address).toSet(), {
      'one.example',
      'two.example',
    });
  });

  test('parses JSON array subscription using Xray codec', () {
    const payload = '''[
      {
        "protocol": "vless",
        "tag": "JSON node",
        "settings": {
          "address": "json.example",
          "port": 443,
          "id": "33333333-3333-4333-8333-333333333333",
          "encryption": "none"
        }
      }
    ]''';

    final result = const SubscriptionParser().parse(payload);
    expect(result.profiles, hasLength(1));
    expect(result.profiles.single.name, 'JSON node');
  });

  test('turns loopback subscription nodes into notices', () {
    const info =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@localhost:80'
        '?encryption=none&security=none&type=tcp#📅 Осталось: 23 дня';
    const support =
        'vless://bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb@127.0.0.1:4444'
        '?encryption=none&security=none&type=tcp#➡️ t.me/TestVpnBot';
    final result = const SubscriptionParser().parse('$info\n$support\n$first');

    expect(result.profiles, hasLength(1));
    expect(result.profiles.single.name, 'One');
    expect(result.notices, ['📅 Осталось: 23 дня', '➡️ t.me/TestVpnBot']);
    expect(result.supportUrl, isNull);
  });

  test('parses // comment metadata without inferring support', () {
    final result = const SubscriptionParser().parse('''
//profile-title: JSON style
//support-url: https://support.example/help
//subscription-userinfo: upload=1; download=2; total=10
$first
''');

    expect(result.profileTitle, 'JSON style');
    expect(result.supportUrl, 'https://support.example/help');
    expect(result.userInfo, contains('total=10'));
  });

  test('rejects payload without supported nodes', () {
    expect(
      () => const SubscriptionParser().parse('<html>login</html>'),
      throwsA(isA<FormatException>()),
    );
  });
}
