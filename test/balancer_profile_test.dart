import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';

void main() {
  test('balancer profile keeps direct fallback through JSON round-trip', () {
    const balancer = BalancerProfile(
      id: 'pool',
      name: 'Pool',
      memberIds: ['one', 'two'],
      fallbackTarget: BalancerProfile.fallbackDirect,
    );

    final restored = BalancerProfile.fromJson(balancer.toJson());

    expect(restored.fallbackTarget, BalancerProfile.fallbackDirect);
    expect(restored.fallbackProfileId, isNull);
  });

  test('balancer profile extracts profile fallback id', () {
    final balancer = BalancerProfile(
      id: 'pool',
      name: 'Pool',
      memberIds: const ['one', 'two'],
      fallbackTarget: BalancerProfile.fallbackProfile('reserve'),
    );

    expect(balancer.fallbackProfileId, 'reserve');
  });

  test('clearing a deleted fallback does not change member profiles', () {
    final balancer = BalancerProfile(
      id: 'pool',
      name: 'Pool',
      memberIds: const ['one', 'two'],
      fallbackTarget: BalancerProfile.fallbackProfile('reserve'),
    );

    final updated = balancer.copyWith(clearFallback: true);

    expect(updated.memberIds, ['one', 'two']);
    expect(updated.fallbackTarget, isNull);
  });

  test('balancer profile supports one member and group sources', () {
    const balancer = BalancerProfile(
      id: 'single-pool',
      name: 'Single pool',
      memberIds: ['one'],
      memberGroupKeys: ['manual:group:Work'],
    );

    final restored = BalancerProfile.fromJson(balancer.toJson());

    expect(restored.memberIds, ['one']);
    expect(restored.memberGroupKeys, ['manual:group:Work']);
  });
}
