import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/profiles/vless_link_parser.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
      '?encryption=none&security=none&type=tcp#Test';

  test('import does not trigger automatic latency refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final probe = _CountingLatencyProbe();
    final profiles = await ProfilesController.load(
      latencyProbe: probe,
    );
    addTearDown(profiles.dispose);

    await profiles.importVlessLink(link);
    await Future<void>.delayed(Duration.zero);

    expect(probe.calls, 0);
    expect(profiles.profiles.single.latencyMs, isNull);
    expect(profiles.profiles.single.pingStatus, PingStatus.unknown);
  });

  test('creates each supported Xray outbound profile manually', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    const uuid = '11111111-1111-4111-8111-111111111111';
    final manualProfiles = [
      const TunnelProfile(
        id: 'manual-vless',
        name: 'VLESS',
        address: 'vless.example',
        port: 443,
        userId: uuid,
      ),
      const TunnelProfile(
        id: 'manual-vmess',
        name: 'VMess',
        address: 'vmess.example',
        port: 443,
        userId: uuid,
        outboundProtocol: OutboundProtocol.vmess,
      ),
      const TunnelProfile(
        id: 'manual-trojan',
        name: 'Trojan',
        address: 'trojan.example',
        port: 443,
        userId: '',
        outboundProtocol: OutboundProtocol.trojan,
        password: 'secret',
        security: 'tls',
      ),
      const TunnelProfile(
        id: 'manual-ss',
        name: 'Shadowsocks',
        address: 'ss.example',
        port: 8388,
        userId: '',
        outboundProtocol: OutboundProtocol.shadowsocks,
        encryption: 'aes-256-gcm',
        password: 'secret',
      ),
      const TunnelProfile(
        id: 'manual-socks',
        name: 'SOCKS5',
        address: 'socks.example',
        port: 1080,
        userId: 'alice',
        outboundProtocol: OutboundProtocol.socks,
        password: 'secret',
      ),
      const TunnelProfile(
        id: 'manual-http',
        name: 'HTTP',
        address: 'http.example',
        port: 3128,
        userId: 'alice',
        outboundProtocol: OutboundProtocol.http,
        password: 'secret',
      ),
    ];

    for (final profile in manualProfiles) {
      await profiles.createProfile(profile);
    }

    expect(
      profiles.profiles.map((profile) => profile.outboundProtocol).toSet(),
      OutboundProtocol.values.toSet(),
    );
  });

  test('in-flight latency result is ignored after controller disposal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final completer = Completer<LatencyProbeResult>();
    final probe = _ControlledLatencyProbe(completer);
    final profiles = await ProfilesController.load(
      latencyProbe: probe,
    );
    final profile = const VlessLinkParser().parse(link);
    await profiles.createProfile(profile);

    final refresh = profiles.refreshLatency(profile.id);
    await Future<void>.delayed(Duration.zero);
    profiles.dispose();
    completer.complete(const LatencyProbeResult.success(52));

    await expectLater(refresh, completes);
  });

  test('default load does not schedule an initial latency refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final saved = const VlessLinkParser().parse(link);
    final seed = await ProfilesController.load();
    await seed.createProfile(saved);
    seed.dispose();

    final probe = _CountingLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: probe);
    profiles.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(probe.calls, 0);
  });

  test('timeout ping status persists across profile reload', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      latencyProbe: _FixedLatencyProbe(const LatencyProbeResult.timeout()),
    );
    final profile = await profiles.importVlessLink(link);

    await profiles.refreshLatency(profile.id);

    expect(profiles.profiles.single.latencyMs, isNull);
    expect(profiles.profiles.single.pingStatus, PingStatus.timeout);
    profiles.dispose();

    final restored = await ProfilesController.load();
    addTearDown(restored.dispose);
    expect(restored.profiles.single.latencyMs, isNull);
    expect(restored.profiles.single.pingStatus, PingStatus.timeout);
  });

  test('skipped protected probe retains the previous direct ping', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      latencyProbe: const _SkippedLatencyProbe(),
    );
    addTearDown(profiles.dispose);
    final profile = await profiles.importVlessLink(link);
    await profiles.updateProfile(
      profile.copyWith(
        latencyMs: 143,
        pingStatus: PingStatus.success,
      ),
    );

    await profiles.refreshLatency(profile.id);

    expect(profiles.profiles.single.latencyMs, 143);
    expect(profiles.profiles.single.pingStatus, PingStatus.success);
  });

  test('reimport preserves a legacy ID for the same connection', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final parsed = const VlessLinkParser().parse(link);
    await profiles.createProfile(parsed.copyWith(id: 'legacy-profile-id'));
    final reimported = await profiles.importVlessLink(link);

    expect(reimported.id, 'legacy-profile-id');
    expect(profiles.profiles, hasLength(1));
  });

  test('adding another profile does not change the active selection', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
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
    final profiles = await ProfilesController.load();
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
      profiles.balancers
          .singleWhere((item) => item.id == balancer.id)
          .fallbackTarget,
      isNull,
    );
  });

  test('balancer probe rejects local destinations', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );

    await expectLater(
      profiles.saveBalancer(
        name: 'Unsafe',
        memberIds: [first.id, second.id],
        strategy: BalancerStrategy.leastPing,
        probeUrl: 'http://127.0.0.1:8080/health',
        probeIntervalSeconds: 5,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('balancer probe interval is clamped to 30 seconds', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    final balancer = await profiles.saveBalancer(
      name: 'Safe',
      memberIds: [first.id, second.id],
      strategy: BalancerStrategy.leastPing,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 5,
    );

    expect(balancer.probeIntervalSeconds, 30);
  });
}

class _CountingLatencyProbe extends LatencyProbe {
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    calls += 1;
    return const LatencyProbeResult.success(42);
  }
}

class _ControlledLatencyProbe extends LatencyProbe {
  _ControlledLatencyProbe(this.completer);

  final Completer<LatencyProbeResult> completer;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) => completer.future;
}

class _FixedLatencyProbe extends LatencyProbe {
  const _FixedLatencyProbe(this.result);

  final LatencyProbeResult result;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async => result;
}

class _SkippedLatencyProbe extends LatencyProbe {
  const _SkippedLatencyProbe();

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) =>
      Future<LatencyProbeResult>.error(const LatencyMeasurementSkipped());
}
