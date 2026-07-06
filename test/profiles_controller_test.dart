import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const link =
      'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Test';

  test('automatic latency refresh can be disabled for deterministic callers',
      () async {
    SharedPreferences.setMockInitialValues({});
    final probe = _CountingLatencyProbe();
    final profiles = await ProfilesController.load(
      latencyProbe: probe,
      automaticLatencyRefresh: false,
    );
    addTearDown(profiles.dispose);

    await profiles.importVlessLink(link);
    await Future<void>.delayed(Duration.zero);

    expect(probe.calls, 0);
    expect(profiles.profiles.single.latencyMs, isNull);
  });

  test('in-flight latency result is ignored after controller disposal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final completer = Completer<int?>();
    final probe = _ControlledLatencyProbe(completer);
    final profiles = await ProfilesController.load(
      latencyProbe: probe,
      automaticLatencyRefresh: false,
    );
    final profile = const VlessLinkParser().parse(link);
    await profiles.createProfile(profile);

    final refresh = profiles.refreshLatency(profile.id);
    await Future<void>.delayed(Duration.zero);
    profiles.dispose();
    completer.complete(52);

    await expectLater(refresh, completes);
  });

  test('disposing cancels the scheduled initial latency refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final saved = const VlessLinkParser().parse(link);
    final seed = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
    await seed.createProfile(saved);
    seed.dispose();

    final probe = _CountingLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: probe);
    profiles.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(probe.calls, 0);
  });

  test('adding another profile does not change the active selection', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = const VlessLinkParser().parse(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    await profiles.createProfile(second);
    await profiles.importVlessLink(
      'vless://33333333-3333-4333-8333-333333333333@third.example:443'
      '?encryption=none&security=none&type=tcp#Third',
    );

    expect(profiles.selectedTarget?.id, first.id);
  });

  test('balancer fallback survives persistence and does not steal selection',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      automaticLatencyRefresh: false,
    );
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = const VlessLinkParser().parse(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    final fallback = const VlessLinkParser().parse(
      'vless://33333333-3333-4333-8333-333333333333@fallback.example:443'
      '?encryption=none&security=none&type=tcp#Fallback',
    );
    await profiles.createProfile(second);
    await profiles.createProfile(fallback);

    final balancer = await profiles.saveBalancer(
      name: 'Pool',
      memberIds: [first.id, second.id],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
      fallbackTarget: BalancerProfile.fallbackProfile(fallback.id),
    );

    expect(profiles.selectedTarget?.id, first.id);
    expect(
      profiles.targetById(balancer.id)?.fallbackProfile?.id,
      fallback.id,
    );

    await profiles.delete(fallback.id);

    expect(
      profiles.balancers.singleWhere((item) => item.id == balancer.id)
          .fallbackTarget,
      isNull,
    );
  });
}

class _CountingLatencyProbe extends LatencyProbe {
  int calls = 0;

  @override
  Future<int?> measure(TunnelProfile profile) async {
    calls += 1;
    return 42;
  }
}

class _ControlledLatencyProbe extends LatencyProbe {
  _ControlledLatencyProbe(this.completer);

  final Completer<int?> completer;

  @override
  Future<int?> measure(TunnelProfile profile) => completer.future;
}
