import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_models.dart';
import 'latency_probe.dart';
import 'profile_repository.dart';
import 'vless_link_parser.dart';

class ProfilesController extends ChangeNotifier {
  ProfilesController._({
    required ProfileRepository repository,
    required List<TunnelProfile> profiles,
    required List<BalancerProfile> balancers,
    required String? selectedId,
    required LatencyProbe latencyProbe,
    required bool automaticLatencyRefresh,
  })  : _repository = repository,
        _profiles = List<TunnelProfile>.from(profiles),
        _balancers = List<BalancerProfile>.from(balancers),
        _selectedId = selectedId,
        _latencyProbe = latencyProbe,
        _automaticLatencyRefresh = automaticLatencyRefresh {
    if (_automaticLatencyRefresh) {
      _pingTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(refreshAllLatencies()),
      );
      if (_profiles.isNotEmpty) {
        _initialPingTimer = Timer(
          const Duration(milliseconds: 700),
          () => unawaited(refreshAllLatencies()),
        );
      }
    }
  }

  final ProfileRepository _repository;
  final VlessLinkParser _parser = const VlessLinkParser();
  final LatencyProbe _latencyProbe;
  final List<TunnelProfile> _profiles;
  final List<BalancerProfile> _balancers;
  String? _selectedId;
  final bool _automaticLatencyRefresh;
  Timer? _pingTimer;
  Timer? _initialPingTimer;
  bool _refreshingLatency = false;
  bool _disposed = false;

  static Future<ProfilesController> load({
    LatencyProbe latencyProbe = const LatencyProbe(),
    bool automaticLatencyRefresh = true,
  }) async {
    final repository = await ProfileRepository.load();
    final profiles = repository.readProfiles();
    final balancers = repository.readBalancers();
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
      selectedId: selectedId,
      latencyProbe: latencyProbe,
      automaticLatencyRefresh: automaticLatencyRefresh,
    );
  }

  List<TunnelProfile> get profiles => List.unmodifiable(_profiles);
  List<BalancerProfile> get balancers => List.unmodifiable(_balancers);
  bool get refreshingLatency => _refreshingLatency;

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
    final members = <TunnelProfile>[];
    for (final id in balancer.memberIds) {
      final profile = _profileById(id);
      if (profile != null) members.add(profile);
    }
    if (members.length < 2) return null;
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

  Future<TunnelProfile> importVlessLink(String link) async {
    final previousSelection = _selectedId;
    final profile = _parser.parse(link);
    final existingIndex = _profiles.indexWhere((item) => item.id == profile.id);
    if (existingIndex >= 0) {
      final old = _profiles[existingIndex];
      _profiles[existingIndex] = profile.copyWith(latencyMs: old.latencyMs);
    } else {
      _profiles.insert(0, profile);
    }
    if (previousSelection == null || targetById(previousSelection) == null) {
      _selectedId = profile.id;
    }
    await _persist();
    _notifyListeners();
    if (_automaticLatencyRefresh) unawaited(refreshLatency(profile.id));
    return profile;
  }

  Future<TunnelProfile> createProfile(TunnelProfile profile) async {
    if (_profiles.any((item) => item.id == profile.id)) {
      throw const FormatException('Профиль с таким ID уже существует');
    }
    _profiles.insert(0, profile);
    if (_selectedId == null || targetById(_selectedId!) == null) {
      _selectedId = profile.id;
    }
    await _persist();
    _notifyListeners();
    if (_automaticLatencyRefresh) unawaited(refreshLatency(profile.id));
    return profile;
  }

  Future<void> updateProfile(TunnelProfile profile) async {
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) return;
    _profiles[index] = profile;
    await _repository.saveProfiles(_profiles);
    _notifyListeners();
    if (_automaticLatencyRefresh) unawaited(refreshLatency(profile.id));
  }

  Future<BalancerProfile> saveBalancer({
    String? id,
    required String name,
    required List<String> memberIds,
    required BalancerStrategy strategy,
    required String probeUrl,
    required int probeIntervalSeconds,
    String? fallbackTarget,
  }) async {
    final uniqueMembers = memberIds
        .toSet()
        .where((value) => _profileById(value) != null)
        .toList(growable: false);
    if (name.trim().isEmpty) {
      throw const FormatException('Укажи имя балансировщика');
    }
    if (uniqueMembers.length < 2) {
      throw const FormatException('Выбери минимум два профиля');
    }
    final uri = Uri.tryParse(probeUrl.trim());
    final needsObservation = strategy == BalancerStrategy.leastPing ||
        (fallbackTarget?.trim().isNotEmpty ?? false);
    if (needsObservation &&
        (uri == null || !uri.hasScheme || !uri.hasAuthority)) {
      throw const FormatException('Некорректный URL проверки');
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
      strategy: strategy,
      probeUrl: probeUrl.trim(),
      probeIntervalSeconds: probeIntervalSeconds.clamp(5, 3600).toInt(),
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
    _selectedId = id;
    await _repository.saveSelectedId(id);
    _notifyListeners();
  }

  Future<void> delete(String id) async {
    final wasProfile = _profiles.any((item) => item.id == id);
    _profiles.removeWhere((profile) => profile.id == id);
    _balancers.removeWhere((balancer) => balancer.id == id);
    if (wasProfile) {
      _balancers.removeWhere((balancer) {
        final remaining =
            balancer.memberIds.where((member) => member != id).length;
        return remaining < 2;
      });
      for (var index = 0; index < _balancers.length; index++) {
        final balancer = _balancers[index];
        final memberRemoved = balancer.memberIds.contains(id);
        final fallbackRemoved = balancer.fallbackProfileId == id;
        if (memberRemoved || fallbackRemoved) {
          _balancers[index] = balancer.copyWith(
            memberIds: memberRemoved
                ? balancer.memberIds
                    .where((member) => member != id)
                    .toList()
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

  Future<void> refreshLatency(String id) async {
    if (_disposed) return;
    final index = _profiles.indexWhere((profile) => profile.id == id);
    if (index < 0) return;
    final profile = _profiles[index];
    final latency = await _latencyProbe.measure(profile);
    if (_disposed) return;
    final currentIndex = _profiles.indexWhere((item) => item.id == id);
    if (currentIndex < 0) return;
    _profiles[currentIndex] = _profiles[currentIndex].copyWith(
      latencyMs: latency,
      clearLatency: latency == null,
    );
    await _repository.saveProfiles(_profiles);
    if (_disposed) return;
    _notifyListeners();
  }

  Future<void> refreshAllLatencies() async {
    if (_disposed || _refreshingLatency || _profiles.isEmpty) return;
    _refreshingLatency = true;
    _notifyListeners();
    try {
      for (final profile in List<TunnelProfile>.from(_profiles)) {
        final latency = await _latencyProbe.measure(profile);
        if (_disposed) return;
        final index = _profiles.indexWhere((item) => item.id == profile.id);
        if (index >= 0) {
          _profiles[index] = _profiles[index].copyWith(
            latencyMs: latency,
            clearLatency: latency == null,
          );
          _notifyListeners();
        }
      }
      if (!_disposed) await _repository.saveProfiles(_profiles);
    } finally {
      _refreshingLatency = false;
      _notifyListeners();
    }
  }

  Future<void> _persist() async {
    if (_disposed) return;
    await _repository.saveProfiles(_profiles);
    await _repository.saveBalancers(_balancers);
    await _repository.saveSelectedId(_selectedId);
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pingTimer?.cancel();
    _initialPingTimer?.cancel();
    super.dispose();
  }
}
