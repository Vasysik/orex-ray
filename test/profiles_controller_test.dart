import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/latency_probe.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/profiles/subscription_source.dart';
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

  test('imports Xray JSON arrays atomically and preserves existing ping', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final existing = await profiles.importVlessLink(link);
    await profiles.updateProfile(
      existing.copyWith(
        latencyMs: 88,
        pingStatus: PingStatus.success,
      ),
    );

    final result = await profiles.importXrayJson(
      '''[
        {
          "protocol": "vless",
          "tag": "Renamed",
          "settings": {
            "address": "example.com",
            "port": 443,
            "id": "11111111-1111-4111-8111-111111111111",
            "encryption": "none"
          }
        },
        {
          "protocol": "trojan",
          "tag": "Trojan JSON",
          "settings": {
            "address": "trojan-json.example",
            "port": 443,
            "password": "secret"
          },
          "streamSettings": {
            "security": "tls",
            "tlsSettings": {"serverName": "trojan-json.example"}
          }
        }
      ]
      ''',
    );

    expect(result.addedCount, 1);
    expect(result.updatedCount, 1);
    expect(profiles.profiles, hasLength(2));
    final updated = profiles.profiles.singleWhere((item) => item.id == existing.id);
    expect(updated.name, 'Renamed');
    expect(updated.latencyMs, 88);
    expect(updated.pingStatus, PingStatus.success);
  });

  test('subscription refresh replaces only nodes owned by that source', () async {
    SharedPreferences.setMockInitialValues({});
    const first =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443'
        '?encryption=none&security=none&type=tcp#One';
    const second =
        'vless://bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb@two.example:443'
        '?encryption=none&security=none&type=tcp#Two';
    const third =
        'vless://cccccccc-cccc-4ccc-8ccc-cccccccccccc@three.example:443'
        '?encryption=none&security=none&type=tcp#Three';
    final source = _SequenceSubscriptionSource([
      SubscriptionFetchResult(
        body: '$first\n$second',
        profileTitle: 'Demo subscription',
      ),
      SubscriptionFetchResult(
        body: '$second\n$third',
        profileTitle: 'Demo subscription',
      ),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);
    await profiles.importVlessLink(link);

    final imported = await profiles.importSubscription('https://sub.example/user');
    expect(imported.addedCount, 2);
    expect(profiles.subscriptions.single.name, 'Demo subscription');
    expect(profiles.profiles.map((profile) => profile.name).toSet(), {
      'Test',
      'One',
      'Two',
    });

    final refreshed = await profiles.refreshSubscription(
      profiles.subscriptions.single.id,
    );
    expect(refreshed.addedCount, 1);
    expect(refreshed.updatedCount, 1);
    expect(refreshed.removedCount, 1);
    expect(profiles.profiles.map((profile) => profile.name).toSet(), {
      'Test',
      'Two',
      'Three',
    });
    expect(profiles.subscriptions.single.profileIds, hasLength(2));
  });


  test('body metadata overrides HTTP header metadata', () async {
    SharedPreferences.setMockInitialValues({});
    const subscribed = '''
#profile-title: Body title
#subscription-userinfo: upload=1; download=2; total=30
#support-url: https://body.example/support
vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443?encryption=none&security=none&type=tcp#One
''';
    final source = _SequenceSubscriptionSource([
      const SubscriptionFetchResult(
        body: subscribed,
        profileTitle: 'Header title',
        userInfo: 'upload=10; download=20; total=300',
        supportUrl: 'https://header.example/support',
      ),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/metadata-priority');
    final subscription = profiles.subscriptions.single;
    expect(subscription.name, 'Body title');
    expect(subscription.userInfo, contains('total=30'));
    expect(subscription.supportUrl, 'https://body.example/support');
  });

  test('full subscription refresh clears support when provider stops sending it',
      () async {
    SharedPreferences.setMockInitialValues({});
    const subscribed =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443'
        '?encryption=none&security=none&type=tcp#One';
    final source = _SequenceSubscriptionSource([
      const SubscriptionFetchResult(
        body: subscribed,
        supportUrl: 'https://support.example/help',
      ),
      const SubscriptionFetchResult(body: subscribed),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/support');
    expect(
      profiles.subscriptions.single.supportUrl,
      'https://support.example/help',
    );

    await profiles.refreshSubscription(profiles.subscriptions.single.id);
    expect(profiles.subscriptions.single.supportUrl, isEmpty);
  });

  test('auto-refresh updates stale subscriptions on app-resume checks', () async {
    SharedPreferences.setMockInitialValues({});
    const first =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443'
        '?encryption=none&security=none&type=tcp#One';
    const second =
        'vless://bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb@two.example:443'
        '?encryption=none&security=none&type=tcp#Two';
    final source = _SequenceSubscriptionSource([
      const SubscriptionFetchResult(body: first),
      const SubscriptionFetchResult(body: second),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/auto');
    final importedAt = DateTime.fromMillisecondsSinceEpoch(
      profiles.subscriptions.single.lastUpdatedEpochMs!,
    );
    final tooSoon = await profiles.refreshSubscriptionsIfDue(
      minimumIntervalHours: 12,
      now: importedAt.add(const Duration(hours: 11)),
    );
    expect(tooSoon, isEmpty);
    expect(source.userAgents, hasLength(1));

    final refreshed = await profiles.refreshSubscriptionsIfDue(
      minimumIntervalHours: 12,
      now: importedAt.add(const Duration(hours: 13)),
    );
    expect(refreshed, hasLength(1));
    expect(profiles.profiles.single.name, 'Two');
    expect(source.userAgents, hasLength(2));
  });

  test('auto-refresh respects a longer provider interval', () async {
    SharedPreferences.setMockInitialValues({});
    const first =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443'
        '?encryption=none&security=none&type=tcp#One';
    const second =
        'vless://bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb@two.example:443'
        '?encryption=none&security=none&type=tcp#Two';
    final source = _SequenceSubscriptionSource([
      const SubscriptionFetchResult(body: first, updateIntervalHours: 24),
      const SubscriptionFetchResult(body: second, updateIntervalHours: 24),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/provider-interval');
    final importedAt = DateTime.fromMillisecondsSinceEpoch(
      profiles.subscriptions.single.lastUpdatedEpochMs!,
    );
    expect(
      await profiles.refreshSubscriptionsIfDue(
        minimumIntervalHours: 6,
        now: importedAt.add(const Duration(hours: 12)),
      ),
      isEmpty,
    );
    expect(source.userAgents, hasLength(1));

    expect(
      await profiles.refreshSubscriptionsIfDue(
        minimumIntervalHours: 6,
        now: importedAt.add(const Duration(hours: 25)),
      ),
      hasLength(1),
    );
    expect(profiles.profiles.single.name, 'Two');
  });

  test('foreground metadata refresh uses HEAD data without replacing servers', () async {
    SharedPreferences.setMockInitialValues({});
    const first =
        'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@one.example:443'
        '?encryption=none&security=none&type=tcp#One';
    final source = _SequenceSubscriptionSource(
      [
        const SubscriptionFetchResult(
          body: first,
          userInfo: 'download=10; total=100',
        ),
      ],
      metadataResponses: const [
        SubscriptionMetadataResult(
          userInfo: 'upload=10; download=20; total=100; expire=2000000000',
          supportUrl: 'https://support.example/help',
          webPageUrl: 'https://panel.example/user',
        ),
      ],
    );
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/metadata');
    final imported = profiles.subscriptions.single;
    final checkedAt = DateTime.fromMillisecondsSinceEpoch(
      imported.lastMetadataCheckEpochMs!,
    );

    expect(
      await profiles.refreshSubscriptionMetadataIfDue(
        now: checkedAt.add(const Duration(minutes: 11)),
      ),
      1,
    );
    expect(profiles.profiles.single.name, 'One');
    expect(profiles.subscriptions.single.parsedUserInfo?.usedBytes, 30);
    expect(
      profiles.subscriptions.single.supportUrl,
      'https://support.example/help',
    );
    expect(source.metadataUserAgents, ['OrexRay/Subscription']);

    expect(
      await profiles.refreshSubscriptionMetadataIfDue(
        now: checkedAt.add(const Duration(minutes: 15)),
      ),
      0,
    );
    expect(source.metadataUserAgents, hasLength(1));
  });

  test('subscription retries once with a v2rayN-compatible user agent', () async {
    SharedPreferences.setMockInitialValues({});
    const subscribed =
        'vless://eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee@sub.example:443'
        '?encryption=none&security=none&type=tcp#Fallback';
    final source = _SequenceSubscriptionSource([
      const SubscriptionFetchResult(body: '<html>browser page</html>'),
      const SubscriptionFetchResult(body: subscribed),
    ]);
    final profiles = await ProfilesController.load(subscriptionSource: source);
    addTearDown(profiles.dispose);

    await profiles.importSubscription('https://sub.example/fallback');

    expect(source.userAgents, hasLength(2));
    expect(source.userAgents.first, 'OrexRay/Subscription');
    expect(source.userAgents.last, startsWith('v2rayN/'));
    expect(profiles.profiles.single.name, 'Fallback');
  });

  test('subscription groups can be reordered and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      subscriptionSource: _SequenceSubscriptionSource([
        const SubscriptionFetchResult(
          body: 'vless://11111111-1111-4111-8111-111111111111@one.example:443?encryption=none&security=none&type=tcp#One',
          profileTitle: 'First',
        ),
        const SubscriptionFetchResult(
          body: 'vless://22222222-2222-4222-8222-222222222222@two.example:443?encryption=none&security=none&type=tcp#Two',
          profileTitle: 'Second',
        ),
      ]),
    );
    await profiles.importSubscription('https://first.example/sub');
    await profiles.importSubscription('https://second.example/sub');
    final before = profiles.subscriptions.map((item) => item.id).toList();
    expect(before, hasLength(2));

    await profiles.reorderSubscriptions(0, 1);
    final after = profiles.subscriptions.map((item) => item.id).toList();
    expect(after, [before[1], before[0]]);
    profiles.dispose();

    final restored = await ProfilesController.load();
    addTearDown(restored.dispose);
    expect(restored.subscriptions.map((item) => item.id).toList(), after);
  });

  test('deleting a subscription keeps manually imported profiles', () async {
    SharedPreferences.setMockInitialValues({});
    const subscribed =
        'vless://dddddddd-dddd-4ddd-8ddd-dddddddddddd@sub.example:443'
        '?encryption=none&security=none&type=tcp#Subscribed';
    final profiles = await ProfilesController.load(
      subscriptionSource: _SequenceSubscriptionSource([
        SubscriptionFetchResult(body: subscribed),
      ]),
    );
    addTearDown(profiles.dispose);
    final manual = await profiles.importVlessLink(link);
    await profiles.importSubscription('https://sub.example/list');

    await profiles.deleteSubscription(profiles.subscriptions.single.id);

    expect(profiles.subscriptions, isEmpty);
    expect(profiles.profiles, hasLength(1));
    expect(profiles.profiles.single.id, manual.id);
  });

  test('exporting all profiles always returns a JSON array', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    await profiles.importVlessLink(link);

    final exported = profiles.exportXrayJson();
    final decoded = jsonDecode(exported);
    expect(decoded, isA<List>());
    expect(decoded as List, hasLength(1));
  });

  test('Xray JSON export round-trips through controller', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    await profiles.importVlessLink(link);
    await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );

    final exported = profiles.exportXrayJson();
    expect(exported.trimLeft().startsWith('['), isTrue);

    SharedPreferences.setMockInitialValues({});
    final restored = await ProfilesController.load();
    addTearDown(restored.dispose);
    final result = await restored.importXrayJson(exported);

    expect(result.addedCount, 2);
    expect(restored.profiles.map((item) => item.name).toSet(), {'Test', 'Second'});
  });

  test('selected Xray export keeps only requested profiles and stays an array',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );

    final decoded = jsonDecode(profiles.exportSelectedXrayJson([first.id]));
    expect(decoded, isA<List>());
    expect(decoded as List, hasLength(1));
    expect(jsonEncode(decoded), contains('example.com'));
    expect(jsonEncode(decoded), isNot(contains('second.example')));
  });

  test('bulk latency refresh probes only selected profiles', () async {
    SharedPreferences.setMockInitialValues({});
    final probe = _RecordingLatencyProbe();
    final profiles = await ProfilesController.load(latencyProbe: probe);
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );

    await profiles.refreshLatencies([first.id]);

    expect(probe.profileIds, [first.id]);
    expect(
      profiles.profiles.singleWhere((item) => item.id == first.id).latencyMs,
      42,
    );
    expect(
      profiles.profiles.singleWhere((item) => item.id == second.id).latencyMs,
      isNull,
    );
  });

  test('bulk delete rewrites balancers once and clears removed fallback',
      () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);

    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    final third = await profiles.importVlessLink(
      'vless://33333333-3333-4333-8333-333333333333@third.example:443'
      '?encryption=none&security=none&type=tcp#Third',
    );
    final balancer = await profiles.saveBalancer(
      name: 'Bulk pool',
      memberIds: [first.id, second.id, third.id],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
      fallbackTarget: BalancerProfile.fallbackProfile(first.id),
    );

    await profiles.deleteProfiles([first.id]);

    expect(profiles.profiles.map((item) => item.id), isNot(contains(first.id)));
    final updated = profiles.balancers.singleWhere(
      (item) => item.id == balancer.id,
    );
    expect(updated.memberIds.toSet(), {second.id, third.id});
    expect(updated.fallbackTarget, isNull);
    expect(profiles.selectedTarget?.id, isNot(first.id));
  });

  test('reorders direct profiles and persists their order', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    expect(profiles.profiles.map((item) => item.id), [second.id, first.id]);

    await profiles.reorderProfiles(0, 1);
    expect(profiles.profiles.map((item) => item.id), [first.id, second.id]);
    profiles.dispose();

    final reloaded = await ProfilesController.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.profiles.map((item) => item.id), [first.id, second.id]);
  });

  test('manual groups persist and subscription profiles stay auto-owned', () async {
    SharedPreferences.setMockInitialValues({});
    const subscribed =
        'vless://dddddddd-dddd-4ddd-8ddd-dddddddddddd@sub.example:443'
        '?encryption=none&security=none&type=tcp#Subscribed';
    final profiles = await ProfilesController.load(
      subscriptionSource: _SequenceSubscriptionSource([
        const SubscriptionFetchResult(body: subscribed),
      ]),
    );
    final manual = await profiles.importVlessLink(link);
    await profiles.importSubscription('https://sub.example/list');
    final subscribedId = profiles.subscriptions.single.profileIds.single;

    expect(await profiles.setProfilesGroup([manual.id], 'Личное'), 1);
    expect(await profiles.setProfilesGroup([subscribedId], 'Личное'), 0);
    expect(
      profiles.profiles.singleWhere((item) => item.id == manual.id).groupName,
      'Личное',
    );
    expect(profiles.isSubscriptionProfile(subscribedId), isTrue);
    profiles.dispose();

    final restored = await ProfilesController.load();
    addTearDown(restored.dispose);
    expect(
      restored.profiles.singleWhere((item) => item.id == manual.id).groupName,
      'Личное',
    );
  });

  test('deleting a manual group can keep or remove its profiles', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);
    final keep = await profiles.importVlessLink(link);
    final remove = await profiles.importVlessLink(
      'vless://99999999-9999-4999-8999-999999999999@remove.example:443'
      '?encryption=none&security=none&type=tcp#Remove',
    );
    await profiles.setProfilesGroup([keep.id], 'Keep');
    await profiles.setProfilesGroup([remove.id], 'Remove');

    await profiles.deleteProfileGroup('Keep');
    expect(profiles.targetById(keep.id), isNotNull);
    expect(
      profiles.profiles.singleWhere((item) => item.id == keep.id).groupName,
      isEmpty,
    );

    await profiles.deleteProfileGroup(
      'Remove',
      deleteProfilesWithGroup: true,
    );
    expect(profiles.targetById(remove.id), isNull);
  });

  test('balancer can be saved with one explicit profile', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);
    final first = await profiles.importVlessLink(link);

    final balancer = await profiles.saveBalancer(
      name: 'Single',
      memberIds: [first.id],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
    );

    expect(profiles.targetById(balancer.id)?.profiles.single.id, first.id);
  });

  test('balancer supports one profile and dynamic folder membership', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);
    final first = await profiles.importVlessLink(link);
    await profiles.setProfilesGroup([first.id], 'Pool');
    final groupKey = profiles.profileGroups.single.key;

    final balancer = await profiles.saveBalancer(
      name: 'Folder pool',
      memberIds: const [],
      memberGroupKeys: [groupKey],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
    );
    expect(profiles.targetById(balancer.id)?.profiles.map((e) => e.id), [first.id]);

    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    await profiles.setProfilesGroup([second.id], 'Pool');

    expect(
      profiles.targetById(balancer.id)?.profiles.map((e) => e.id).toSet(),
      {first.id, second.id},
    );
  });

  test('deleting a kept folder preserves balancer members explicitly', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);
    final first = await profiles.importVlessLink(link);
    await profiles.setProfilesGroup([first.id], 'Pool');
    final groupKey = profiles.profileGroups.single.key;
    final balancer = await profiles.saveBalancer(
      name: 'Folder pool',
      memberIds: const [],
      memberGroupKeys: [groupKey],
      strategy: BalancerStrategy.random,
      probeUrl: 'https://www.gstatic.com/generate_204',
      probeIntervalSeconds: 30,
    );

    await profiles.deleteProfileGroup('Pool');

    final stored = profiles.balancers.singleWhere((item) => item.id == balancer.id);
    expect(stored.memberGroupKeys, isEmpty);
    expect(stored.memberIds, contains(first.id));
    expect(profiles.targetById(balancer.id), isNotNull);
  });

  test('reorders profile groups as persisted profile blocks', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    final third = await profiles.importVlessLink(
      'vless://33333333-3333-4333-8333-333333333333@third.example:443'
      '?encryption=none&security=none&type=tcp#Third',
    );
    await profiles.setProfilesGroup([first.id], 'A');
    await profiles.setProfilesGroup([second.id], 'B');
    await profiles.setProfilesGroup([third.id], 'C');

    final before = profiles.profileGroups.map((group) => group.key).toList();
    expect(before, hasLength(3));
    await profiles.reorderProfileGroups(before, 0, 2);
    final after = profiles.profileGroups.map((group) => group.key).toList();
    expect(after, [before[1], before[2], before[0]]);
    expect(
      profiles.manualGroupNames,
      after.map((key) => key.substring('manual:group:'.length)).toList(),
    );
    profiles.dispose();

    final restored = await ProfilesController.load();
    addTearDown(restored.dispose);
    expect(
      restored.profileGroups.map((group) => group.key).toList(),
      after,
    );
  });

  test('manual group reorder preserves subscription-owned profiles', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load(
      subscriptionSource: _SequenceSubscriptionSource([
        const SubscriptionFetchResult(
          body: 'vless://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@sub.example:443?encryption=none&security=none&type=tcp#Sub',
          profileTitle: 'Subscription',
        ),
      ]),
    );
    addTearDown(profiles.dispose);
    await profiles.importSubscription('https://sub.example/list');
    final first = await profiles.importVlessLink(
      'vless://11111111-1111-4111-8111-111111111111@one.example:443?encryption=none&security=none&type=tcp#One',
    );
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@two.example:443?encryption=none&security=none&type=tcp#Two',
    );
    await profiles.setProfilesGroup([first.id], 'A');
    await profiles.setProfilesGroup([second.id], 'B');
    final manualKeys = profiles.profileGroups
        .where((group) => group.isManualGroup)
        .map((group) => group.key)
        .toList();
    expect(manualKeys, hasLength(2));
    final subscribedId = profiles.subscriptions.single.profileIds.single;

    await profiles.reorderProfileGroups(manualKeys, 0, 1);

    final afterManual = profiles.profileGroups
        .where((group) => group.isManualGroup)
        .map((group) => group.key)
        .toList();
    expect(afterManual, [manualKeys[1], manualKeys[0]]);
    expect(profiles.targetById(subscribedId), isNotNull);
  });

  test('reorders profiles only inside the requested group scope', () async {
    SharedPreferences.setMockInitialValues({});
    final profiles = await ProfilesController.load();
    addTearDown(profiles.dispose);
    final first = await profiles.importVlessLink(link);
    final second = await profiles.importVlessLink(
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?encryption=none&security=none&type=tcp#Second',
    );
    final third = await profiles.importVlessLink(
      'vless://33333333-3333-4333-8333-333333333333@third.example:443'
      '?encryption=none&security=none&type=tcp#Third',
    );
    await profiles.setProfilesGroup([first.id, third.id], 'Group');

    final before = profiles.profiles.map((item) => item.id).toList();
    final scoped = before
        .where((id) => id == first.id || id == third.id)
        .toList();
    await profiles.reorderProfilesInScope(scoped, 0, 1);
    final after = profiles.profiles.map((item) => item.id).toList();

    expect(
      after.where((id) => id == first.id || id == third.id).toList(),
      scoped.reversed.toList(),
    );
    expect(after.indexOf(second.id), before.indexOf(second.id));
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

class _SequenceSubscriptionSource extends SubscriptionSource {
  _SequenceSubscriptionSource(
    this.responses, {
    this.metadataResponses = const [],
  });

  final List<SubscriptionFetchResult> responses;
  final List<SubscriptionMetadataResult?> metadataResponses;
  final List<String> userAgents = <String>[];
  final List<String> metadataUserAgents = <String>[];
  int _index = 0;
  int _metadataIndex = 0;

  @override
  Future<SubscriptionFetchResult> loadUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async {
    userAgents.add(userAgent);
    if (_index >= responses.length) {
      throw StateError('No subscription response left for $value');
    }
    return responses[_index++];
  }

  @override
  Future<SubscriptionMetadataResult?> loadMetadataUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async {
    metadataUserAgents.add(userAgent);
    if (_metadataIndex >= metadataResponses.length) return null;
    return metadataResponses[_metadataIndex++];
  }
}

class _CountingLatencyProbe extends LatencyProbe {
  int calls = 0;

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    calls += 1;
    return const LatencyProbeResult.success(42);
  }
}

class _RecordingLatencyProbe extends LatencyProbe {
  final List<String> profileIds = [];

  @override
  Future<LatencyProbeResult> measure(TunnelProfile profile) async {
    profileIds.add(profile.id);
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
