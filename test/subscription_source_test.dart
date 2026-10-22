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
        ..headers.set('support-url', 'https://support.example/help')
        ..headers.set('profile-web-page-url', 'https://panel.example/user')
        ..headers.set('announce', 'Maintenance tonight')
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
    expect(result.supportUrl, 'https://support.example/help');
    expect(result.webPageUrl, 'https://panel.example/user');
    expect(result.announce, 'Maintenance tonight');
  });

  test('decodes base64 metadata from HTTP headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final userInfo = base64.encode(
      utf8.encode('upload=10; download=20; total=100; expire=2000000000'),
    );
    final support = base64.encode(utf8.encode('https://support.example/help'));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('subscription-userinfo', 'base64:$userInfo')
        ..headers.set('support-url', 'base64:$support')
        ..write('payload');
      await request.response.close();
    });

    final result = await SubscriptionSource().loadUrl(
      'http://127.0.0.1:${server.port}/subscription',
    );
    expect(result.userInfo, contains('total=100'));
    expect(result.supportUrl, 'https://support.example/help');
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

  test('refreshes subscription metadata with HEAD without downloading body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var headRequests = 0;
    server.listen((request) async {
      expect(request.method, 'HEAD');
      headRequests += 1;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('subscription-userinfo', 'upload=10; download=20; total=100; expire=2000000000')
        ..headers.set('support-url', 'https://support.example/help')
        ..headers.set('profile-web-page-url', 'https://panel.example/user');
      await request.response.close();
    });

    final result = await SubscriptionSource().loadMetadataUrl(
      'http://127.0.0.1:${server.port}/subscription',
    );

    expect(headRequests, 1);
    expect(result, isNotNull);
    expect(result!.userInfo, contains('total=100'));
    expect(result.supportUrl, 'https://support.example/help');
    expect(result.webPageUrl, 'https://panel.example/user');
  });

  test('HEAD unsupported defers metadata until the next full refresh', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });

    final result = await SubscriptionSource().loadMetadataUrl(
      'http://127.0.0.1:${server.port}/subscription',
    );

    expect(result, isNull);
  });
}
