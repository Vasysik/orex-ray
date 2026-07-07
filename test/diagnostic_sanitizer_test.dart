import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/diagnostics/tunnel_diagnostics.dart';

void main() {
  test('redacts UUIDs, VLESS links and secret fields', () {
    const uuid = '11111111-1111-4111-8111-111111111111';
    final sanitized = DiagnosticSanitizer.sanitize(
      'id=$uuid vless://$uuid@example.com:443 password=secret',
    );

    expect(sanitized, isNot(contains(uuid)));
    expect(sanitized, contains('<UUID>'));
    expect(sanitized, contains('vless://<REDACTED>'));
    expect(sanitized, isNot(contains('secret')));
  });
}
