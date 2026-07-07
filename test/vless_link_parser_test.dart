import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';

void main() {
  const parser = VlessLinkParser();

  test('parses VLESS REALITY RAW link', () {
    final profile = parser.parse(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&flow=xtls-rprx-vision&security=reality'
      '&sni=www.microsoft.com&fp=chrome&pbk=public-key&sid=abcd&type=tcp'
      '#My%20Server',
    );

    expect(profile.name, 'My Server');
    expect(profile.address, 'example.com');
    expect(profile.port, 443);
    expect(profile.security, 'reality');
    expect(profile.transport, 'raw');
    expect(profile.realityPassword, 'public-key');
    expect(profile.flow, 'xtls-rprx-vision');
  });

  test('same UUID on different endpoints gets different IDs', () {
    final first = parser.parse(
      'vless://11111111-1111-4111-8111-111111111111@one.example:443'
      '?encryption=none&security=none&type=tcp#One',
    );
    final second = parser.parse(
      'vless://11111111-1111-4111-8111-111111111111@two.example:8443'
      '?encryption=none&security=none&type=ws&path=%2Fws#Two',
    );

    expect(first.id, isNot(second.id));
    expect(first.id, hasLength(32));
    expect(second.id, hasLength(32));
  });

  test('rejects oversized VLESS input', () {
    final oversized = 'vless://${List.filled(64 * 1024, 'a').join()}';
    expect(
      () => parser.parse(oversized),
      throwsA(isA<VlessLinkFormatException>()),
    );
  });

  test('rejects non-VLESS links', () {
    expect(
      () => parser.parse('https://example.com'),
      throwsA(isA<VlessLinkFormatException>()),
    );
  });
}
