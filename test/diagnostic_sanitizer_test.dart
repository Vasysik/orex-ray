import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/diagnostics/tunnel_diagnostics.dart';

void main() {
  test('redacts UUIDs, VLESS links and secret fields', () {
    const uuid = '11111111-1111-4111-8111-111111111111';
    final sanitized = DiagnosticSanitizer.sanitize(
      'id=$uuid vless://$uuid@example.com:443 password=secret',
    );

    expect(sanitized, isNot(contains(uuid)));
    expect(sanitized, contains('id=<REDACTED>'));
    expect(sanitized, contains('vless://<REDACTED>'));
    expect(sanitized, isNot(contains('secret')));
  });

  test('redacts credentials in every supported imported link scheme', () {
    const links = [
      'vmess://eyJpZCI6InNlY3JldCJ9',
      'trojan://secret@trojan.example:443',
      'ss://YWVzLTI1Ni1nY206c2VjcmV0@ss.example:8388',
      'socks5://alice:secret@socks.example:1080',
      'https://alice:secret@proxy.example:443',
    ];

    final sanitized = DiagnosticSanitizer.sanitize(links.join(' '));

    expect(sanitized, isNot(contains('secret')));
    expect(sanitized, contains('vmess://<REDACTED>'));
    expect(sanitized, contains('trojan://<REDACTED>'));
    expect(sanitized, contains('ss://<REDACTED>'));
    expect(sanitized, contains('socks5://<REDACTED>'));
    expect(sanitized, contains('https://<REDACTED>'));
  });
}
