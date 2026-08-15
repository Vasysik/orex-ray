import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profile_repository.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
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

  test('saves profiles and selected target without changing credentials',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profile = const VlessLinkParser().parse(
      'vless://22222222-2222-4222-8222-222222222222@secure.example:8443'
      '?encryption=none&security=reality&sni=secure.example&fp=chrome'
      '&pbk=secret-public-key&sid=abcd&type=tcp#Secure',
    );

    final repository = await ProfileRepository.load();
    await repository.saveProfiles([profile]);
    await repository.saveSelectedId(profile.id);

    final reloaded = await ProfileRepository.load();
    expect(reloaded.readProfiles().single.userId, profile.userId);
    expect(
      reloaded.readProfiles().single.realityPassword,
      profile.realityPassword,
    );
    expect(reloaded.readSelectedId(), profile.id);
  });

  test('migrates VLESS JSON written before outbound protocol support', () {
    final profile = TunnelProfile.fromJson({
      'id': 'legacy-vless',
      'name': 'Legacy VLESS',
      'address': 'legacy.example',
      'port': 443,
      'userId': '11111111-1111-4111-8111-111111111111',
      'encryption': 'none',
      'security': 'tls',
      'transport': 'raw',
    });

    expect(profile.outboundProtocol, OutboundProtocol.vless);
    expect(profile.password, isEmpty);
    expect(profile.vmessSecurity, 'auto');
    expect(profile.toJson().containsKey('outboundProtocol'), isFalse);
    expect(profile.toJson().containsKey('password'), isFalse);
  });
}
