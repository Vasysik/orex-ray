import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/subscription_source.dart';

void main() {
  test('downloads subscription without requiring a file extension', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.headers.value(HttpHeaders.userAgentHeader), 'OrexRay/Subscription');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('profile-title', 'Demo subscription')
        ..headers.set('subscription-userinfo', 'download=10; total=100')
        ..headers.set('profile-update-interval', '12')
        ..write('vless://example');
      await request.response.close();
    });

    final result = await SubscriptionSource().loadUrl(
      'http://127.0.0.1:${server.port}/sub?id=123',
    );

    expect(result.body, 'vless://example');
    expect(result.profileTitle, 'Demo subscription');
    expect(result.userInfo, contains('total=100'));
    expect(result.updateIntervalHours, 12);
  });

  test('decodes base64 profile-title metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final title = base64.encode(utf8.encode('Моя подписка'));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('profile-title', 'base64:$title')
        ..write('payload');
      await request.response.close();
    });

    final result = await SubscriptionSource().loadUrl(
      'http://127.0.0.1:${server.port}/subscription',
    );
    expect(result.profileTitle, 'Моя подписка');
  });
}
