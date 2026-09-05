import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/xray_json_source.dart';

void main() {
  test('loads JSON from an HTTP URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"outbounds":[]}');
      await request.response.close();
    });

    final payload = await XrayJsonSource().loadUrl(
      'http://127.0.0.1:${server.port}/config',
    );

    expect(payload, '{"outbounds":[]}');
  });

  test('rejects non-success HTTP responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    await expectLater(
      XrayJsonSource().loadUrl(
        'http://127.0.0.1:${server.port}/missing.json',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 404'),
        ),
      ),
    );
  });

  test('rejects non HTTP URL schemes', () async {
    await expectLater(
      XrayJsonSource().loadUrl('file:///tmp/config.json'),
      throwsA(isA<FormatException>()),
    );
  });
}
