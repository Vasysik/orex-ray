import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profile_repository.dart';
import 'package:orex_ray/core/profiles/proxy_subscription.dart';
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

  test('persists subscription URL and owned profile ids', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = await ProfileRepository.load();
    const subscription = ProxySubscription(
      id: 'sub-test',
      url: 'https://example.com/sub?token=secret',
      name: 'Example',
      profileIds: ['one', 'two'],
      updateIntervalHours: 12,
      userInfo: 'download=1; total=2',
      notices: ['Осталось: 23 дня'],
    );

    await repository.saveSubscriptions([subscription]);
    final reloaded = await ProfileRepository.load();
    final restored = reloaded.readSubscriptions().single;

    expect(restored.url, subscription.url);
    expect(restored.profileIds, ['one', 'two']);
    expect(restored.updateIntervalHours, 12);
    expect(restored.notices, ['Осталось: 23 дня']);
  });

  test('persists manual profile group name', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = await ProfileRepository.load();
    final profile = const VlessLinkParser().parse(
      'vless://33333333-3333-4333-8333-333333333333@group.example:443'
      '?encryption=none&security=none&type=tcp#Grouped',
    ).copyWith(groupName: 'Работа');

    await repository.saveProfiles([profile]);
    final reloaded = await ProfileRepository.load();

    expect(reloaded.readProfiles().single.groupName, 'Работа');
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
