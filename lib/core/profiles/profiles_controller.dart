import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_models.dart';
import 'latency_probe.dart';
import 'profile_repository.dart';
import 'proxy_link_parser.dart';
import 'proxy_subscription.dart';
import 'subscription_parser.dart';
import 'subscription_source.dart';
import 'xray_json_codec.dart';

class XrayJsonImportResult {
  const XrayJsonImportResult({
    required this.addedCount,
    required this.updatedCount,
    required this.skippedUnsupported,
  });

  final int addedCount;
  final int updatedCount;
  final int skippedUnsupported;

  int get changedCount => addedCount + updatedCount;
}


class SubscriptionSyncResult {
  const SubscriptionSyncResult({
    required this.subscription,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
    required this.skippedUnsupported,
  });

  final ProxySubscription subscription;
  final int addedCount;
  final int updatedCount;
  final int removedCount;
  final int skippedUnsupported;
}

class _LoadedSubscription {
  const _LoadedSubscription({required this.fetched, required this.parsed});

  final SubscriptionFetchResult fetched;
  final SubscriptionParseResult parsed;
}

class ProfileGroupInfo {
  const ProfileGroupInfo({
    required this.key,
    required this.title,
    required this.profileIds,
    required this.subscription,
  });

  final String key;
  final String title;
  final List<String> profileIds;
  final ProxySubscription? subscription;

  bool get isSubscription => subscription != null;
  bool get isManualGroup => key.startsWith('manual:group:');
}

class ProfilesController extends ChangeNotifier {
  ProfilesController._({
    required ProfileRepository repository,
    required List<TunnelProfile> profiles,
    required List<BalancerProfile> balancers,
    required List<ProxySubscription> subscriptions,
    required String? selectedId,
    required LatencyProbe latencyProbe,
    required SubscriptionSource subscriptionSource,
  })  : _repository = repository,
        _profiles = List<TunnelProfile>.from(profiles),
        _balancers = List<BalancerProfile>.from(balancers),
        _subscriptions = List<ProxySubscription>.from(subscriptions),
        _selectedId = selectedId,
        _latencyProbe = latencyProbe,
        _subscriptionSource = subscriptionSource;

  final ProfileRepository _repository;
  final ProxyLinkParser _parser = const ProxyLinkParser();
  final XrayJsonCodec _xrayJsonCodec = const XrayJsonCodec();
  final SubscriptionParser _subscriptionParser = const SubscriptionParser();
  final SubscriptionSource _subscriptionSource;
  final LatencyProbe _latencyProbe;
  final List<TunnelProfile> _profiles;
  final List<BalancerProfile> _balancers;
  final List<ProxySubscription> _subscriptions;
  String? _selectedId;
  static const _maxProfiles = 500;
  bool _refreshingLatency = false;
  bool _refreshingSubscriptions = false;
  bool _autoRefreshInFlight = false;
  final Set<String> _refreshingSubscriptionIds = <String>{};
  final Map<String, int> _lastAutoRefreshAttemptEpochMs = <String, int>{};
  bool _disposed = false;

  static Future<ProfilesController> load({
    LatencyProbe latencyProbe = const LatencyProbe(),
    SubscriptionSource? subscriptionSource,
  }) async {
    final repository = await ProfileRepository.load();
    final profiles = repository.readProfiles();
    final balancers = repository.readBalancers();
    final subscriptions = repository.readSubscriptions();
    var selectedId = repository.readSelectedId();
    final allIds = <String>{
      ...profiles.map((item) => item.id),
      ...balancers.map((item) => item.id),
    };
    if (allIds.isNotEmpty && !allIds.contains(selectedId)) {
      selectedId = profiles.isNotEmpty ? profiles.first.id : balancers.first.id;
    }
    return ProfilesController._(
      repository: repository,
      profiles: profiles,
      balancers: balancers,
      subscriptions: subscriptions,
      selectedId: selectedId,
      latencyProbe: latencyProbe,
      subscriptionSource: subscriptionSource ?? SubscriptionSource(),
    );
  }

  List<TunnelProfile> get profiles => List.unmodifiable(_profiles);
  List<BalancerProfile> get balancers => List.unmodifiable(_balancers);
  List<ProxySubscription> get subscriptions => List.unmodifiable(_subscriptions);
  bool get refreshingLatency => _refreshingLatency;
  bool get refreshingSubscriptions => _refreshingSubscriptions;
  bool subscriptionRefreshing(String id) =>
      _refreshingSubscriptions || _refreshingSubscriptionIds.contains(id);

  ProxySubscription? subscriptionForProfile(String profileId) {
    for (final subscription in _subscriptions) {
      if (subscription.profileIds.contains(profileId)) return subscription;
    }
    return null;
  }

  bool isSubscriptionProfile(String profileId) =>
      subscriptionForProfile(profileId) != null;

  List<ProfileGroupInfo> get profileGroups {
    final subscriptionByProfileId = <String, ProxySubscription>{
      for (final subscription in _subscriptions)
        for (final profileId in subscription.profileIds) profileId: subscription,
    };
    final groupedIds = <String, List<String>>{};
    final titles = <String, String>{};
    final subscriptionsByKey = <String, ProxySubscription?>{};

    for (final profile in _profiles) {
      final subscription = subscriptionByProfileId[profile.id];
      late final String key;
      late final String title;
      if (subscription != null) {
        key = 'subscription:${subscription.id}';
        title = subscription.name;
      } else {
        final groupName = profile.groupName.trim();
        if (groupName.isEmpty) {
          key = 'manual:ungrouped';
          title = 'Без группы';
        } else {
          key = 'manual:group:$groupName';
          title = groupName;
        }
      }
      groupedIds.putIfAbsent(key, () => <String>[]).add(profile.id);
      titles[key] = title;
      subscriptionsByKey[key] = subscription;
    }

    return List.unmodifiable([
      for (final entry in groupedIds.entries)
        ProfileGroupInfo(
          key: entry.key,
          title: titles[entry.key]!,
          profileIds: List.unmodifiable(entry.value),
          subscription: subscriptionsByKey[entry.key],
        ),
    ]);
  }

  String profileGroupKey(String profileId) {
    final subscription = subscriptionForProfile(profileId);
    if (subscription != null) return 'subscription:${subscription.id}';
    final profile = _profileById(profileId);
    if (profile == null || profile.groupName.trim().isEmpty) {
      return 'manual:ungrouped';
    }
    return 'manual:group:${profile.groupName.trim()}';
  }

  List<String> effectiveBalancerMemberIds(BalancerProfile balancer) {
    final ids = <String>{
      for (final id in balancer.memberIds)
        if (_profileById(id) != null) id,
    };
    if (balancer.memberGroupKeys.isNotEmpty) {
      final groupsByKey = <String, ProfileGroupInfo>{
        for (final group in profileGroups) group.key: group,
      };
      for (final key in balancer.memberGroupKeys) {
        final group = groupsByKey[key];
        if (group != null) ids.addAll(group.profileIds);
      }
    }
    return List.unmodifiable(ids);
  }

  List<TunnelProfile> effectiveBalancerMembers(BalancerProfile balancer) {
    final members = <TunnelProfile>[];
    for (final id in effectiveBalancerMemberIds(balancer)) {
      final profile = _profileById(id);
      if (profile != null) members.add(profile);
    }
    return List.unmodifiable(members);
  }

  List<String> get manualGroupNames => List.unmodifiable(
        profileGroups
            .where((group) => group.isManualGroup)
            .map((group) => group.title),
      );

  Future<int> setProfilesGroup(
    Iterable<String> profileIds,
    String? groupName,
  ) async {
    final normalized = groupName?.trim() ?? '';
    if (normalized.length > 80) {
      throw const FormatException('Название группы слишком длинное');
    }
    final ids = profileIds.toSet();
    if (ids.isEmpty) return 0;
    final subscriptionIds = <String>{
      for (final subscription in _subscriptions) ...subscription.profileIds,
    };
    var changed = 0;
    for (var index = 0; index < _profiles.length; index++) {
      final profile = _profiles[index];
      if (!ids.contains(profile.id) || subscriptionIds.contains(profile.id)) {
        continue;
      }
      if (profile.groupName == normalized) continue;
      _profiles[index] = normalized.isEmpty
          ? profile.copyWith(clearGroup: true)
          : profile.copyWith(groupName: normalized);
      changed += 1;
    }
    if (changed == 0) return 0;
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
    return changed;
  }

  Future<void> renameProfileGroup(String oldName, String newName) async {
    final oldValue = oldName.trim();
    final newValue = newName.trim();
    if (oldValue.isEmpty || newValue.isEmpty) {
      throw const FormatException('Укажи название группы');
    }
    if (newValue.length > 80) {
      throw const FormatException('Название группы слишком длинное');
    }
    if (oldValue == newValue) return;
    for (var index = 0; index < _profiles.length; index++) {
      final profile = _profiles[index];
      if (profile.groupName == oldValue && !isSubscriptionProfile(profile.id)) {
        _profiles[index] = profile.copyWith(groupName: newValue);
      }
    }
    final oldKey = 'manual:group:$oldValue';
    final newKey = 'manual:group:$newValue';
    for (var index = 0; index < _balancers.length; index++) {
      final balancer = _balancers[index];
      if (!balancer.memberGroupKeys.contains(oldKey)) continue;
      _balancers[index] = balancer.copyWith(
        memberGroupKeys: {
          for (final key in balancer.memberGroupKeys)
            if (key == oldKey) newKey else key,
        }.toList(growable: false),
      );
    }
    await _repository.saveProfiles(_profiles);
    await _repository.saveBalancers(_balancers);
    _notifyListeners();
  }

  Future<void> deleteProfileGroup(
    String name, {
    bool deleteProfilesWithGroup = false,
  }) async {
    final normalized = name.trim();
    final ids = _profiles
        .where(
          (profile) => profile.groupName == normalized &&
              !isSubscriptionProfile(profile.id),
        )
        .map((profile) => profile.id)
        .toSet();
    if (ids.isEmpty) return;
    final groupKey = 'manual:group:$normalized';
    for (var index = 0; index < _balancers.length; index++) {
      final balancer = _balancers[index];
      if (!balancer.memberGroupKeys.contains(groupKey)) continue;
      _balancers[index] = balancer.copyWith(
        memberIds: deleteProfilesWithGroup
            ? balancer.memberIds
            : <String>{...balancer.memberIds, ...ids}.toList(growable: false),
        memberGroupKeys: balancer.memberGroupKeys
            .where((key) => key != groupKey)
            .toList(growable: false),
      );
    }
    if (deleteProfilesWithGroup) {
      await deleteProfiles(ids);
      return;
    }
    await setProfilesGroup(ids, null);
    await _repository.saveBalancers(_balancers);
  }

  Future<void> reorderProfileGroups(
    List<String> sectionKeys,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= sectionKeys.length) return;
    if (newIndex < 0 || newIndex >= sectionKeys.length || oldIndex == newIndex) {
      return;
    }

    final reorderedKeys = List<String>.from(sectionKeys);
    final moved = reorderedKeys.removeAt(oldIndex);
    reorderedKeys.insert(newIndex, moved);
    final sectionKeySet = sectionKeys.toSet();
    final profilesBySection = <String, List<TunnelProfile>>{};
    final outside = <TunnelProfile>[];
    for (final profile in _profiles) {
      final key = profileGroupKey(profile.id);
      if (!sectionKeySet.contains(key)) {
        outside.add(profile);
        continue;
      }
      profilesBySection.putIfAbsent(key, () => <TunnelProfile>[]).add(profile);
    }

    if (outside.isNotEmpty) return;
    final reordered = <TunnelProfile>[
      for (final key in reorderedKeys) ...?profilesBySection[key],
    ];
    if (reordered.length != _profiles.length) return;
    _profiles
      ..clear()
      ..addAll(reordered);
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
  }

  Future<void> reorderProfilesInScope(
    List<String> scopeIds,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= scopeIds.length) return;
    if (newIndex < 0 ||
        newIndex >= scopeIds.length ||
        newIndex == oldIndex) {
      return;
    }
    final reorderedIds = List<String>.from(scopeIds);
    final moved = reorderedIds.removeAt(oldIndex);
    reorderedIds.insert(newIndex, moved);
    final byId = <String, TunnelProfile>{
      for (final profile in _profiles) profile.id: profile,
    };
    var replacementIndex = 0;
    for (var index = 0; index < _profiles.length; index++) {
      if (!scopeIds.contains(_profiles[index].id)) continue;
      final replacement = byId[reorderedIds[replacementIndex++]];
      if (replacement != null) _profiles[index] = replacement;
    }
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
  }

  /// Whether the injected direct TCP probe is protected from an active VPN
  /// TUN. See [LatencyProbe.canMeasureWhileVpnActive].
  bool get canMeasureLatencyWhileVpnActive =>
      _latencyProbe.canMeasureWhileVpnActive;

  List<TunnelTarget> get targets => [
        ..._profiles.map(TunnelTarget.single),
        ..._balancers.map(_resolveBalancer).whereType<TunnelTarget>(),
      ];

  TunnelTarget? targetById(String id) {
    for (final target in targets) {
      if (target.id == id) return target;
    }
    return null;
  }

  TunnelTarget? get selectedTarget {
    final id = _selectedId;
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return TunnelTarget.single(profile);
    }
    for (final balancer in _balancers) {
      if (balancer.id == id) return _resolveBalancer(balancer);
    }
    return null;
  }

  TunnelProfile? get selectedProfile {
    final target = selectedTarget;
    return target != null && !target.isBalancer ? target.primaryProfile : null;
  }

  TunnelTarget? _resolveBalancer(BalancerProfile balancer) {
    final members = effectiveBalancerMembers(balancer);
    if (members.isEmpty) return null;
    final fallbackProfileId = balancer.fallbackProfileId;
    final fallbackProfile =
        fallbackProfileId == null ? null : _profileById(fallbackProfileId);
    return TunnelTarget.balancer(
      balancer,
      members,
      fallbackProfile: fallbackProfile,
    );
  }

  TunnelProfile? _profileById(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<SubscriptionSyncResult> importSubscription(String url) async {
    final normalizedUrl = url.trim();
    final existingIndex = _subscriptions.indexWhere(
      (subscription) => subscription.url == normalizedUrl,
    );
    final existing = existingIndex >= 0 ? _subscriptions[existingIndex] : null;
    final id = existing?.id ?? ProxySubscription.idForUrl(normalizedUrl);
    final loaded = await _loadSubscription(normalizedUrl);
    return _applySubscription(
      id: id,
      url: normalizedUrl,
      existing: existing,
      fetched: loaded.fetched,
      parsed: loaded.parsed,
    );
  }

  Future<SubscriptionSyncResult> refreshSubscription(String id) async {
    if (_refreshingSubscriptionIds.contains(id)) {
      throw const FormatException('Подписка уже обновляется');
    }
    ProxySubscription? existing;
    for (final item in _subscriptions) {
      if (item.id == id) {
        existing = item;
        break;
      }
    }
    if (existing == null) {
      throw const FormatException('Подписка не найдена');
    }
    _refreshingSubscriptionIds.add(id);
    _notifyListeners();
    try {
      final loaded = await _loadSubscription(existing.url);
      return await _applySubscription(
        id: existing.id,
        url: existing.url,
        existing: existing,
        fetched: loaded.fetched,
        parsed: loaded.parsed,
      );
    } finally {
      _refreshingSubscriptionIds.remove(id);
      _notifyListeners();
    }
  }

  Future<_LoadedSubscription> _loadSubscription(String url) async {
    const userAgents = <String>[
      'OrexRay/Subscription',
      // Some panels choose the subscription representation from User-Agent.
      // Retry only after the native OrexRay request fails so ordinary
      // providers never receive an impersonated compatibility UA.
      'v2rayN/7.15.2 OrexRay/Subscription',
    ];
    FormatException? firstError;
    for (final userAgent in userAgents) {
      try {
        final fetched = await _subscriptionSource.loadUrl(
          url,
          userAgent: userAgent,
        );
        final parsed = _subscriptionParser.parse(fetched.body);
        return _LoadedSubscription(fetched: fetched, parsed: parsed);
      } on FormatException catch (error) {
        firstError ??= error;
      }
    }
    throw firstError ?? const FormatException('Не удалось прочитать подписку');
  }

  Future<List<SubscriptionSyncResult>> refreshSubscriptionsIfDue({
    required int minimumIntervalHours,
    DateTime? now,
  }) async {
    if (_disposed ||
        minimumIntervalHours <= 0 ||
        _subscriptions.isEmpty ||
        _autoRefreshInFlight) {
      return const [];
    }

    _autoRefreshInFlight = true;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final retryCooldownMs = const Duration(minutes: 15).inMilliseconds;
    final results = <SubscriptionSyncResult>[];
    try {
      for (final subscription
          in List<ProxySubscription>.from(_subscriptions)) {
        if (_disposed) break;
        final providerInterval = subscription.updateIntervalHours ?? 0;
        final effectiveHours = providerInterval > minimumIntervalHours
            ? providerInterval
            : minimumIntervalHours;
        final intervalMs = Duration(hours: effectiveHours).inMilliseconds;
        final lastUpdated = subscription.lastUpdatedEpochMs;
        if (lastUpdated != null && nowMs - lastUpdated < intervalMs) continue;

        final lastAttempt = _lastAutoRefreshAttemptEpochMs[subscription.id];
        if (lastAttempt != null && nowMs - lastAttempt < retryCooldownMs) {
          continue;
        }
        _lastAutoRefreshAttemptEpochMs[subscription.id] = nowMs;

        try {
          results.add(await refreshSubscription(subscription.id));
        } on Object {
          // Automatic refresh is best-effort. Keep the previous subscription
          // intact and let a later app resume/start retry after the cooldown.
        }
      }
      return List.unmodifiable(results);
    } finally {
      _autoRefreshInFlight = false;
    }
  }

  Future<List<SubscriptionSyncResult>> refreshAllSubscriptions() async {
    if (_refreshingSubscriptions ||
        _autoRefreshInFlight ||
        _subscriptions.isEmpty) {
      return const [];
    }
    _refreshingSubscriptions = true;
    _notifyListeners();
    final results = <SubscriptionSyncResult>[];
    try {
      for (final subscription in List<ProxySubscription>.from(_subscriptions)) {
        if (_disposed) break;
        results.add(await refreshSubscription(subscription.id));
      }
      return List.unmodifiable(results);
    } finally {
      _refreshingSubscriptions = false;
      _notifyListeners();
    }
  }

  Future<void> deleteSubscription(String id) async {
    final index = _subscriptions.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final subscription = _subscriptions[index];
    _lastAutoRefreshAttemptEpochMs.remove(subscription.id);
    final removedIds = subscription.profileIds.toSet();
    final workingProfiles = List<TunnelProfile>.from(_profiles)
      ..removeWhere((profile) => removedIds.contains(profile.id));
    final subscriptionGroupKey = 'subscription:${subscription.id}';
    final workingBalancers = _rewriteBalancersAfterProfileRemoval(
      _balancers.map(
        (balancer) => balancer.memberGroupKeys.contains(subscriptionGroupKey)
            ? balancer.copyWith(
                memberGroupKeys: balancer.memberGroupKeys
                    .where((key) => key != subscriptionGroupKey)
                    .toList(growable: false),
              )
            : balancer,
      ),
      removedIds,
    );
    final workingSubscriptions = List<ProxySubscription>.from(_subscriptions)
      ..removeAt(index);
    var selectedId = _selectedId;
    final remainingTargetIds = <String>{
      ...workingProfiles.map((profile) => profile.id),
      ...workingBalancers.map((balancer) => balancer.id),
    };
    if (selectedId == null || !remainingTargetIds.contains(selectedId)) {
      selectedId = workingProfiles.isNotEmpty
          ? workingProfiles.first.id
          : workingBalancers.isNotEmpty
              ? workingBalancers.first.id
              : null;
    }

    await _repository.saveProfiles(workingProfiles);
    await _repository.saveBalancers(workingBalancers);
    await _repository.saveSubscriptions(workingSubscriptions);
    await _repository.saveSelectedId(selectedId);
    if (_disposed) return;
    _profiles
      ..clear()
      ..addAll(workingProfiles);
    _balancers
      ..clear()
      ..addAll(workingBalancers);
    _subscriptions
      ..clear()
      ..addAll(workingSubscriptions);
    _selectedId = selectedId;
    _notifyListeners();
  }

  Future<SubscriptionSyncResult> _applySubscription({
    required String id,
    required String url,
    required ProxySubscription? existing,
    required SubscriptionFetchResult fetched,
    required SubscriptionParseResult parsed,
  }) async {
    if (parsed.profiles.isEmpty) {
      throw const FormatException('В подписке нет поддерживаемых серверов');
    }

    final oldIds = existing?.profileIds.toSet() ?? <String>{};
    final workingProfiles = List<TunnelProfile>.from(_profiles);
    var insertionIndex = workingProfiles.indexWhere(
      (profile) => oldIds.contains(profile.id),
    );
    if (insertionIndex < 0) insertionIndex = 0;
    final oldProfiles = <String, TunnelProfile>{
      for (final profile in workingProfiles)
        if (oldIds.contains(profile.id)) profile.id: profile,
    };
    workingProfiles.removeWhere((profile) => oldIds.contains(profile.id));
    insertionIndex = insertionIndex.clamp(0, workingProfiles.length).toInt();

    final imported = <TunnelProfile>[];
    final newIds = <String>{};
    for (final sourceProfile in parsed.profiles) {
      _validateProfileInput(sourceProfile);
      final derivedId = _subscriptionProfileId(id, sourceProfile.id);
      if (!newIds.add(derivedId)) continue;
      final old = oldProfiles[derivedId];
      imported.add(
        sourceProfile.copyWith(
          id: derivedId,
          latencyMs: old?.latencyMs,
          pingStatus: old?.pingStatus ?? PingStatus.unknown,
          clearLatency: old == null,
        ),
      );
    }
    if (workingProfiles.length + imported.length > _maxProfiles) {
      throw const FormatException('Можно сохранить не больше 500 профилей');
    }
    workingProfiles.insertAll(insertionIndex, imported);

    final removedIds = oldIds.difference(newIds);
    final workingBalancers = _rewriteBalancersAfterProfileRemoval(
      _balancers,
      removedIds,
    );
    final title = _firstNonEmpty([
      fetched.profileTitle,
      parsed.profileTitle,
      existing?.name,
      Uri.tryParse(url)?.host,
      'Подписка',
    ]);
    final subscription = ProxySubscription(
      id: id,
      url: url,
      name: title,
      profileIds: List.unmodifiable(imported.map((profile) => profile.id)),
      lastUpdatedEpochMs: DateTime.now().millisecondsSinceEpoch,
      updateIntervalHours: fetched.updateIntervalHours ??
          parsed.updateIntervalHours ??
          existing?.updateIntervalHours,
      userInfo: fetched.userInfo ?? parsed.userInfo ?? existing?.userInfo ?? '',
      notices: List.unmodifiable(parsed.notices),
    );
    final workingSubscriptions = List<ProxySubscription>.from(_subscriptions);
    final subscriptionIndex =
        workingSubscriptions.indexWhere((item) => item.id == id);
    if (subscriptionIndex >= 0) {
      workingSubscriptions[subscriptionIndex] = subscription;
    } else {
      workingSubscriptions.insert(0, subscription);
    }

    var selectedId = _selectedId;
    final remainingTargetIds = <String>{
      ...workingProfiles.map((profile) => profile.id),
      ...workingBalancers.map((balancer) => balancer.id),
    };
    if (selectedId == null || !remainingTargetIds.contains(selectedId)) {
      selectedId = imported.isNotEmpty
          ? imported.first.id
          : workingProfiles.isNotEmpty
              ? workingProfiles.first.id
              : workingBalancers.isNotEmpty
                  ? workingBalancers.first.id
                  : null;
    }

    await _repository.saveProfiles(workingProfiles);
    await _repository.saveBalancers(workingBalancers);
    await _repository.saveSubscriptions(workingSubscriptions);
    await _repository.saveSelectedId(selectedId);
    if (_disposed) {
      return SubscriptionSyncResult(
        subscription: subscription,
        addedCount: newIds.difference(oldIds).length,
        updatedCount: newIds.intersection(oldIds).length,
        removedCount: removedIds.length,
        skippedUnsupported: parsed.skippedUnsupported,
      );
    }

    _profiles
      ..clear()
      ..addAll(workingProfiles);
    _balancers
      ..clear()
      ..addAll(workingBalancers);
    _subscriptions
      ..clear()
      ..addAll(workingSubscriptions);
    _selectedId = selectedId;
    _notifyListeners();
    return SubscriptionSyncResult(
      subscription: subscription,
      addedCount: newIds.difference(oldIds).length,
      updatedCount: newIds.intersection(oldIds).length,
      removedCount: removedIds.length,
      skippedUnsupported: parsed.skippedUnsupported,
    );
  }

  List<BalancerProfile> _rewriteBalancersAfterProfileRemoval(
    Iterable<BalancerProfile> source,
    Set<String> removedIds,
  ) {
    if (removedIds.isEmpty) return List<BalancerProfile>.from(source);
    final result = <BalancerProfile>[];
    for (final balancer in source) {
      final members = balancer.memberIds
          .where((member) => !removedIds.contains(member))
          .toList(growable: false);
      if (members.isEmpty && balancer.memberGroupKeys.isEmpty) continue;
      final fallbackRemoved = balancer.fallbackProfileId != null &&
          removedIds.contains(balancer.fallbackProfileId);
      result.add(
        balancer.copyWith(
          memberIds: members,
          clearFallback: fallbackRemoved,
        ),
      );
    }
    return result;
  }

  String _subscriptionProfileId(String subscriptionId, String sourceId) {
    return sha256
        .convert(utf8.encode('$subscriptionId:$sourceId'))
        .toString()
        .substring(0, 32);
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Подписка';
  }

  /// Imports every URI format represented by [OutboundProtocol].
  Future<TunnelProfile> importLink(String link) async {
    final previousSelection = _selectedId;
    var profile = _parser.parse(link);
    final legacyIndex = _profiles.indexWhere(
      (item) => _sameConnectionProfile(item, profile),
    );
    if (legacyIndex >= 0 && _profiles[legacyIndex].id != profile.id) {
      profile = profile.copyWith(id: _profiles[legacyIndex].id);
    }
    if (_profiles.length >= _maxProfiles &&
        !_profiles.any((item) => item.id == profile.id)) {
      throw const FormatException('Можно сохранить не больше 500 профилей');
    }
    final existingIndex = _profiles.indexWhere((item) => item.id == profile.id);
    if (existingIndex >= 0) {
      final old = _profiles[existingIndex];
      _profiles[existingIndex] = profile.copyWith(
        groupName: old.groupName,
        latencyMs: old.latencyMs,
        pingStatus: old.pingStatus,
      );
    } else {
      _profiles.insert(0, profile);
    }
    if (previousSelection == null || targetById(previousSelection) == null) {
      _selectedId = profile.id;
    }
    await _persist();
    _notifyListeners();
    return profile;
  }

  /// Imports one Xray config, an outbound object, or an array containing either.
  /// The complete payload is validated before any in-memory changes are applied.
  Future<XrayJsonImportResult> importXrayJson(
    String payload, {
    String sourceLabel = '',
  }) async {
    final decoded = _xrayJsonCodec.decode(
      payload,
      sourceLabel: sourceLabel,
    );
    final working = List<TunnelProfile>.from(_profiles);
    final added = <TunnelProfile>[];
    var updatedCount = 0;

    int findSame(List<TunnelProfile> values, TunnelProfile profile) {
      final exact = values.indexWhere((item) => item.id == profile.id);
      if (exact >= 0) return exact;
      return values.indexWhere((item) => _sameConnectionProfile(item, profile));
    }

    for (var profile in decoded.profiles) {
      _validateProfileInput(profile);
      var index = findSame(working, profile);
      if (index >= 0) {
        final old = working[index];
        working[index] = profile.copyWith(
          id: old.id,
          groupName: old.groupName,
          latencyMs: old.latencyMs,
          pingStatus: old.pingStatus,
        );
        updatedCount += 1;
        continue;
      }

      index = findSame(added, profile);
      if (index >= 0) {
        final old = added[index];
        added[index] = profile.copyWith(id: old.id);
        updatedCount += 1;
        continue;
      }
      added.add(profile);
    }

    if (working.length + added.length > _maxProfiles) {
      throw const FormatException('Можно сохранить не больше 500 профилей');
    }
    working.insertAll(0, added);

    final previousSelection = _selectedId;
    _profiles
      ..clear()
      ..addAll(working);
    if (_profiles.isNotEmpty &&
        (previousSelection == null || targetById(previousSelection) == null)) {
      _selectedId = decoded.profiles.first.id;
      final importedSelection = _profiles.indexWhere(
        (item) => _sameConnectionProfile(item, decoded.profiles.first),
      );
      if (importedSelection >= 0) {
        _selectedId = _profiles[importedSelection].id;
      }
    }

    await _persist();
    _notifyListeners();
    return XrayJsonImportResult(
      addedCount: added.length,
      updatedCount: updatedCount,
      skippedUnsupported: decoded.skippedUnsupported,
    );
  }

  String exportXrayJson({String? profileId}) {
    if (profileId == null) {
      return _xrayJsonCodec.encodeProfiles(_profiles, forceArray: true);
    }
    final profile = _profileById(profileId);
    if (profile == null) {
      throw const FormatException('Профиль для экспорта не найден');
    }
    return _xrayJsonCodec.encodeProfiles([profile]);
  }

  String exportSelectedXrayJson(Iterable<String> profileIds) {
    final ids = profileIds.toSet();
    final selected = _profiles
        .where((profile) => ids.contains(profile.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      throw const FormatException('Нет выбранных профилей для экспорта');
    }
    return _xrayJsonCodec.encodeProfiles(selected, forceArray: true);
  }

  /// Legacy public API retained for callers built when VLESS was the only
  /// supported outbound. It now accepts the same supported link set as the UI.
  Future<TunnelProfile> importVlessLink(String link) => importLink(link);

  Future<TunnelProfile> createProfile(TunnelProfile profile) async {
    _validateProfileInput(profile);
    if (_profiles.length >= _maxProfiles) {
      throw const FormatException('Можно сохранить не больше 500 профилей');
    }
    if (_profiles.any((item) => item.id == profile.id)) {
      throw const FormatException('Профиль с таким ID уже существует');
    }
    _profiles.insert(0, profile);
    if (_selectedId == null || targetById(_selectedId!) == null) {
      _selectedId = profile.id;
    }
    await _persist();
    _notifyListeners();
    return profile;
  }

  Future<void> updateProfile(TunnelProfile profile) async {
    _validateProfileInput(profile);
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) return;
    _profiles[index] = profile;
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
  }

  Future<BalancerProfile> saveBalancer({
    String? id,
    required String name,
    required List<String> memberIds,
    List<String> memberGroupKeys = const [],
    required BalancerStrategy strategy,
    required String probeUrl,
    required int probeIntervalSeconds,
    String? fallbackTarget,
  }) async {
    final uniqueMembers = memberIds
        .toSet()
        .where((value) => _profileById(value) != null)
        .toList(growable: false);
    final availableGroups = <String, ProfileGroupInfo>{
      for (final group in profileGroups) group.key: group,
    };
    final uniqueGroupKeys = memberGroupKeys
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && availableGroups.containsKey(value))
        .toSet()
        .toList(growable: false);
    final effectiveMembers = <String>{...uniqueMembers};
    for (final key in uniqueGroupKeys) {
      effectiveMembers.addAll(availableGroups[key]!.profileIds);
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Укажи имя балансировщика');
    }
    if (name.trim().length > 256) {
      throw const FormatException('Имя балансировщика слишком длинное');
    }
    if (probeUrl.length > 8192) {
      throw const FormatException('URL проверки слишком длинный');
    }
    if (memberIds.length > _maxProfiles) {
      throw const FormatException('Слишком много участников балансировщика');
    }
    if (effectiveMembers.isEmpty) {
      throw const FormatException('Выбери хотя бы один профиль или папку');
    }
    final uri = Uri.tryParse(probeUrl.trim());
    final needsObservation = strategy == BalancerStrategy.leastPing ||
        (fallbackTarget?.trim().isNotEmpty ?? false);
    if (needsObservation && !_isSafeProbeUri(uri)) {
      throw const FormatException(
        'URL проверки должен быть публичным HTTP/HTTPS адресом',
      );
    }

    final normalizedFallback = fallbackTarget?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      final fallbackProfileId = normalizedFallback.startsWith(
        BalancerProfile.fallbackProfilePrefix,
      )
          ? normalizedFallback.substring(
              BalancerProfile.fallbackProfilePrefix.length,
            )
          : null;
      final builtIn = normalizedFallback == BalancerProfile.fallbackDirect ||
          normalizedFallback == BalancerProfile.fallbackBlock;
      if (!builtIn &&
          (fallbackProfileId == null ||
              _profileById(fallbackProfileId) == null)) {
        throw const FormatException('Некорректный fallback балансировщика');
      }
    }

    final previousSelection = _selectedId;
    final balancer = BalancerProfile(
      id: id ?? 'balancer-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      memberIds: uniqueMembers,
      memberGroupKeys: uniqueGroupKeys,
      strategy: strategy,
      probeUrl: probeUrl.trim(),
      probeIntervalSeconds: probeIntervalSeconds.clamp(30, 3600).toInt(),
      fallbackTarget: normalizedFallback == null || normalizedFallback.isEmpty
          ? null
          : normalizedFallback,
    );
    final index = _balancers.indexWhere((item) => item.id == balancer.id);
    if (index >= 0) {
      _balancers[index] = balancer;
    } else {
      _balancers.insert(0, balancer);
    }
    if (previousSelection == null || targetById(previousSelection) == null) {
      _selectedId = balancer.id;
    }
    await _persist();
    _notifyListeners();
    return balancer;
  }

  Future<void> select(String id) async {
    if (_selectedId == id || !targets.any((target) => target.id == id)) {
      return;
    }
    final previousId = _selectedId;
    _selectedId = id;
    // Selection is presentation state first: repaint immediately instead of
    // making the user wait for SharedPreferences I/O before the tile reacts.
    _notifyListeners();
    try {
      await _repository.saveSelectedId(id);
    } catch (_) {
      // Do not leave an in-memory selection that was not persisted. Only
      // roll back if no newer selection superseded this request.
      if (_selectedId == id) {
        _selectedId = previousId;
        _notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final wasProfile = _profiles.any((item) => item.id == id);
    _profiles.removeWhere((profile) => profile.id == id);
    _balancers.removeWhere((balancer) => balancer.id == id);
    if (wasProfile) {
      for (var index = 0; index < _subscriptions.length; index++) {
        final subscription = _subscriptions[index];
        if (subscription.profileIds.contains(id)) {
          _subscriptions[index] = subscription.copyWith(
            profileIds: subscription.profileIds
                .where((profileId) => profileId != id)
                .toList(growable: false),
          );
        }
      }
      _balancers.removeWhere((balancer) {
        final remaining =
            balancer.memberIds.where((member) => member != id).length;
        return remaining == 0 && balancer.memberGroupKeys.isEmpty;
      });
      for (var index = 0; index < _balancers.length; index++) {
        final balancer = _balancers[index];
        final memberRemoved = balancer.memberIds.contains(id);
        final fallbackRemoved = balancer.fallbackProfileId == id;
        if (memberRemoved || fallbackRemoved) {
          _balancers[index] = balancer.copyWith(
            memberIds: memberRemoved
                ? balancer.memberIds.where((member) => member != id).toList()
                : balancer.memberIds,
            clearFallback: fallbackRemoved,
          );
        }
      }
    }
    if (_selectedId == id ||
        !targets.any((target) => target.id == _selectedId)) {
      _selectedId = targets.isEmpty ? null : targets.first.id;
    }
    await _persist();
    _notifyListeners();
  }

  /// Deletes several direct profiles as one repository transaction.
  ///
  /// Balancers that lose too many members are removed, while valid balancers
  /// are rewritten once after every selected profile has been removed.
  Future<void> deleteProfiles(Iterable<String> ids) async {
    final removedIds = ids.toSet()
      ..retainAll(_profiles.map((profile) => profile.id).toSet());
    if (removedIds.isEmpty) return;

    _profiles.removeWhere((profile) => removedIds.contains(profile.id));
    for (var index = 0; index < _subscriptions.length; index++) {
      final subscription = _subscriptions[index];
      if (subscription.profileIds.any(removedIds.contains)) {
        _subscriptions[index] = subscription.copyWith(
          profileIds: subscription.profileIds
              .where((profileId) => !removedIds.contains(profileId))
              .toList(growable: false),
        );
      }
    }
    _balancers.removeWhere((balancer) {
      final remaining = balancer.memberIds
          .where((member) => !removedIds.contains(member))
          .length;
      return remaining == 0 && balancer.memberGroupKeys.isEmpty;
    });
    for (var index = 0; index < _balancers.length; index++) {
      final balancer = _balancers[index];
      final remainingMembers = balancer.memberIds
          .where((member) => !removedIds.contains(member))
          .toList(growable: false);
      final fallbackRemoved = balancer.fallbackProfileId != null &&
          removedIds.contains(balancer.fallbackProfileId);
      if (remainingMembers.length != balancer.memberIds.length ||
          fallbackRemoved) {
        _balancers[index] = balancer.copyWith(
          memberIds: remainingMembers,
          clearFallback: fallbackRemoved,
        );
      }
    }

    if (_selectedId == null ||
        removedIds.contains(_selectedId) ||
        !targets.any((target) => target.id == _selectedId)) {
      _selectedId = targets.isEmpty ? null : targets.first.id;
    }
    await _persist();
    _notifyListeners();
  }

  /// Persists the user-visible order of direct server profiles.
  Future<void> reorderProfiles(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _profiles.length) return;
    if (newIndex < 0 || newIndex >= _profiles.length) return;
    if (oldIndex == newIndex) return;
    final profile = _profiles.removeAt(oldIndex);
    _profiles.insert(newIndex, profile);
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
  }

  /// Refreshes one direct server reachability value.
  ///
  /// [shouldApply] lets a caller discard a result if the network context
  /// changed while the socket was being opened.  This is important when a
  /// VPN is being torn down or brought up: a socket that started as a direct
  /// probe must never be persisted after it has been captured by the TUN.
  Future<void> refreshLatency(
    String id, {
    bool Function()? shouldApply,
  }) async {
    if (_disposed || (shouldApply != null && !shouldApply())) return;
    final index = _profiles.indexWhere((profile) => profile.id == id);
    if (index < 0) return;
    final profile = _profiles[index];
    LatencyProbeResult result;
    try {
      result = await _latencyProbe.measure(profile);
    } on LatencyMeasurementSkipped {
      return;
    }
    if (_disposed || (shouldApply != null && !shouldApply())) return;
    final currentIndex = _profiles.indexWhere((item) => item.id == id);
    if (currentIndex < 0 ||
        (_profiles[currentIndex].latencyMs == result.latencyMs &&
            _profiles[currentIndex].pingStatus == result.status)) {
      return;
    }
    _profiles[currentIndex] = _profiles[currentIndex].copyWith(
      latencyMs: result.latencyMs,
      pingStatus: result.status,
      clearLatency: result.latencyMs == null,
    );
    await _repository.saveProfiles(_profiles);
    if (_disposed) return;
    _notifyListeners();
  }

  Future<void> refreshAllLatencies({bool Function()? shouldApply}) async {
    if (_disposed ||
        _refreshingLatency ||
        _profiles.isEmpty ||
        (shouldApply != null && !shouldApply())) {
      return;
    }
    _refreshingLatency = true;
    _notifyListeners();
    var changed = false;
    try {
      for (final profile in List<TunnelProfile>.from(_profiles)) {
        if (shouldApply != null && !shouldApply()) return;
        LatencyProbeResult result;
        try {
          result = await _latencyProbe.measure(profile);
        } on LatencyMeasurementSkipped {
          // Do not erase useful saved measurements when the protected native
          // probe itself is unavailable. Continue with the remaining profiles
          // because another endpoint can still be measured safely.
          continue;
        }
        if (_disposed || (shouldApply != null && !shouldApply())) return;
        final index = _profiles.indexWhere((item) => item.id == profile.id);
        if (index >= 0 &&
            (_profiles[index].latencyMs != result.latencyMs ||
                _profiles[index].pingStatus != result.status)) {
          _profiles[index] = _profiles[index].copyWith(
            latencyMs: result.latencyMs,
            pingStatus: result.status,
            clearLatency: result.latencyMs == null,
          );
          changed = true;
        }
      }
      if (!_disposed && changed) await _repository.saveProfiles(_profiles);
    } finally {
      _refreshingLatency = false;
      _notifyListeners();
    }
  }

  /// Refreshes only the requested direct profiles and saves their results in
  /// one repository write. This keeps bulk selection actions cheap even for a
  /// large list.
  Future<void> refreshLatencies(
    Iterable<String> ids, {
    bool Function()? shouldApply,
  }) async {
    final requested = ids.toSet();
    if (_disposed ||
        _refreshingLatency ||
        requested.isEmpty ||
        (shouldApply != null && !shouldApply())) {
      return;
    }
    final candidates = _profiles
        .where((profile) => requested.contains(profile.id))
        .toList(growable: false);
    if (candidates.isEmpty) return;

    _refreshingLatency = true;
    _notifyListeners();
    var changed = false;
    try {
      for (final profile in candidates) {
        if (_disposed || (shouldApply != null && !shouldApply())) return;
        LatencyProbeResult result;
        try {
          result = await _latencyProbe.measure(profile);
        } on LatencyMeasurementSkipped {
          continue;
        }
        if (_disposed || (shouldApply != null && !shouldApply())) return;
        final index = _profiles.indexWhere((item) => item.id == profile.id);
        if (index >= 0 &&
            (_profiles[index].latencyMs != result.latencyMs ||
                _profiles[index].pingStatus != result.status)) {
          _profiles[index] = _profiles[index].copyWith(
            latencyMs: result.latencyMs,
            pingStatus: result.status,
            clearLatency: result.latencyMs == null,
          );
          changed = true;
        }
      }
      if (!_disposed && changed) await _repository.saveProfiles(_profiles);
    } finally {
      _refreshingLatency = false;
      _notifyListeners();
    }
  }

  bool _isSafeProbeUri(Uri? uri) {
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return false;
    }

    final address = InternetAddress.tryParse(host);
    if (address == null) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isPublicIpv4(bytes);
    }

    final unspecified = bytes.every((value) => value == 0);
    final loopback =
        bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
    final uniqueLocal = bytes[0] == 0xfc || bytes[0] == 0xfd;
    final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    final multicast = bytes[0] == 0xff;
    final ipv4Mapped = bytes.take(10).every((value) => value == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (ipv4Mapped) {
      return _isPublicIpv4(bytes.sublist(12));
    }
    return !unspecified &&
        !loopback &&
        !uniqueLocal &&
        !linkLocal &&
        !multicast;
  }

  bool _isPublicIpv4(List<int> bytes) {
    final first = bytes[0];
    final second = bytes[1];
    final third = bytes[2];
    return first != 0 &&
        first != 10 &&
        first != 127 &&
        !(first == 100 && second >= 64 && second <= 127) &&
        !(first == 169 && second == 254) &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && second == 0 && third == 0) &&
        !(first == 192 && second == 168) &&
        !(first == 198 && (second == 18 || second == 19)) &&
        first < 224;
  }

  bool _sameConnectionProfile(TunnelProfile left, TunnelProfile right) {
    final leftAlpn = [...left.alpn]..sort();
    final rightAlpn = [...right.alpn]..sort();
    return left.outboundProtocol == right.outboundProtocol &&
        left.address.toLowerCase() == right.address.toLowerCase() &&
        left.port == right.port &&
        left.userId == right.userId &&
        left.password == right.password &&
        left.vmessSecurity == right.vmessSecurity &&
        left.encryption == right.encryption &&
        left.flow == right.flow &&
        left.security == right.security &&
        left.transport == right.transport &&
        left.serverName.toLowerCase() == right.serverName.toLowerCase() &&
        left.fingerprint == right.fingerprint &&
        left.realityPassword == right.realityPassword &&
        left.shortId == right.shortId &&
        left.spiderX == right.spiderX &&
        left.path == right.path &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.serviceName == right.serviceName &&
        left.grpcMode == right.grpcMode &&
        listEquals(leftAlpn, rightAlpn) &&
        left.allowInsecure == right.allowInsecure;
  }

  void _validateProfileInput(TunnelProfile profile) {
    void check(String value, int limit, String fieldName) {
      if (value.length > limit) {
        throw FormatException('$fieldName слишком длинный');
      }
    }

    check(profile.name, 256, 'Имя профиля');
    check(profile.address, 1024, 'Адрес сервера');
    check(profile.sourceLink, 64 * 1024, 'Исходная ссылка');
    for (final field in <(String, String)>[
      ('Идентификатор', profile.userId),
      ('Пароль', profile.password),
      ('VMess security', profile.vmessSecurity),
      ('Encryption', profile.encryption),
      ('Flow', profile.flow),
      ('Security', profile.security),
      ('Transport', profile.transport),
      ('SNI', profile.serverName),
      ('Fingerprint', profile.fingerprint),
      ('REALITY key', profile.realityPassword),
      ('Short ID', profile.shortId),
      ('Spider X', profile.spiderX),
      ('Path', profile.path),
      ('Host', profile.host),
      ('Service name', profile.serviceName),
      ('gRPC mode', profile.grpcMode),
    ]) {
      check(field.$2, 4096, field.$1);
    }
    if (profile.name.trim().isEmpty || profile.address.trim().isEmpty) {
      throw const FormatException('Укажите имя и адрес профиля');
    }
    if (profile.port < 1 || profile.port > 65535) {
      throw const FormatException('Некорректный порт профиля');
    }
    switch (profile.outboundProtocol) {
      case OutboundProtocol.vless || OutboundProtocol.vmess:
        if (profile.userId.trim().isEmpty) {
          throw const FormatException('Для профиля нужен UUID');
        }
      case OutboundProtocol.trojan:
        if (profile.password.isEmpty) {
          throw const FormatException('Для Trojan нужен пароль');
        }
      case OutboundProtocol.shadowsocks:
        if (profile.password.isEmpty || profile.encryption.trim().isEmpty) {
          throw const FormatException('Для Shadowsocks нужны метод и пароль');
        }
      case OutboundProtocol.socks || OutboundProtocol.http:
        if (profile.userId.isEmpty != profile.password.isEmpty) {
          throw const FormatException(
            'Для авторизации нужны имя пользователя и пароль',
          );
        }
    }
    if (!{'none', 'tls', 'reality'}.contains(profile.security)) {
      throw const FormatException('Неподдерживаемый transport security');
    }
    if (!{
      'raw',
      'websocket',
      'grpc',
      'xhttp',
      'httpupgrade',
    }.contains(profile.transport)) {
      throw const FormatException('Неподдерживаемый транспорт профиля');
    }
    if (profile.security == 'reality' &&
        profile.realityPassword.trim().isEmpty) {
      throw const FormatException('Для REALITY нужен public key');
    }
    if (profile.outboundProtocol == OutboundProtocol.vmess &&
        !{
          'auto',
          'aes-128-gcm',
          'chacha20-poly1305',
        }.contains(profile.vmessSecurity)) {
      throw const FormatException('Неподдерживаемый VMess security');
    }
    if (profile.alpn.length > 16 ||
        profile.alpn.any((value) => value.length > 4096)) {
      throw const FormatException(
          'Слишком много или слишком длинные ALPN-значения');
    }
  }

  Future<void> _persist() async {
    if (_disposed) return;
    await _repository.saveProfiles(_profiles);
    await _repository.saveBalancers(_balancers);
    await _repository.saveSubscriptions(_subscriptions);
    await _repository.saveSelectedId(_selectedId);
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
