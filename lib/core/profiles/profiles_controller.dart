import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_models.dart';
import 'latency_probe.dart';
import 'profile_repository.dart';
import 'proxy_link_parser.dart';
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

class ProfilesController extends ChangeNotifier {
  ProfilesController._({
    required ProfileRepository repository,
    required List<TunnelProfile> profiles,
    required List<BalancerProfile> balancers,
    required String? selectedId,
    required LatencyProbe latencyProbe,
  })  : _repository = repository,
        _profiles = List<TunnelProfile>.from(profiles),
        _balancers = List<BalancerProfile>.from(balancers),
        _selectedId = selectedId,
        _latencyProbe = latencyProbe;

  final ProfileRepository _repository;
  final ProxyLinkParser _parser = const ProxyLinkParser();
  final XrayJsonCodec _xrayJsonCodec = const XrayJsonCodec();
  final LatencyProbe _latencyProbe;
  final List<TunnelProfile> _profiles;
  final List<BalancerProfile> _balancers;
  String? _selectedId;
  static const _maxProfiles = 500;
  bool _refreshingLatency = false;
  bool _disposed = false;

  static Future<ProfilesController> load({
    LatencyProbe latencyProbe = const LatencyProbe(),
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
    );
  }

  List<TunnelProfile> get profiles => List.unmodifiable(_profiles);
  List<BalancerProfile> get balancers => List.unmodifiable(_balancers);
  bool get refreshingLatency => _refreshingLatency;

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
    if (name.trim().length > 256) {
      throw const FormatException('Имя балансировщика слишком длинное');
    }
    if (probeUrl.length > 8192) {
      throw const FormatException('URL проверки слишком длинный');
    }
    if (memberIds.length > _maxProfiles) {
      throw const FormatException('Слишком много участников балансировщика');
    }
    if (uniqueMembers.length < 2) {
      throw const FormatException('Выбери минимум два профиля');
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
    _balancers.removeWhere((balancer) {
      final remaining = balancer.memberIds
          .where((member) => !removedIds.contains(member))
          .length;
      return remaining < 2;
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
