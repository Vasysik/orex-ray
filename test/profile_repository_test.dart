import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profile_repository.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('skips malformed saved profiles without losing valid ones', () async {
    final valid = const VlessLinkParser().parse(
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Valid',
    );
    SharedPreferences.setMockInitialValues({
      'orex_ray_profiles_v2': jsonEncode([
        {'broken': true},
        valid.toJson(),
      ]),
    });

    final repository = await ProfileRepository.load();
    final profiles = repository.readProfiles();

    expect(profiles, hasLength(1));
    expect(profiles.single.name, 'Valid');
  });
}
