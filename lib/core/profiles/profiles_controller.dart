import 'package:flutter/foundation.dart';

import '../tunnel/tunnel_models.dart';
import 'profile_repository.dart';
import 'vless_link_parser.dart';

class ProfilesController extends ChangeNotifier {
  ProfilesController._({
    required ProfileRepository repository,
    required List<TunnelProfile> profiles,
    required String? selectedId,
  })  : _repository = repository,
        _profiles = List<TunnelProfile>.from(profiles),
        _selectedId = selectedId;

  final ProfileRepository _repository;
  final VlessLinkParser _parser = const VlessLinkParser();
  final List<TunnelProfile> _profiles;
  String? _selectedId;

  static Future<ProfilesController> load() async {
    final repository = await ProfileRepository.load();
    final profiles = repository.readProfiles();
    var selectedId = repository.readSelectedId();
    if (profiles.isNotEmpty &&
        !profiles.any((profile) => profile.id == selectedId)) {
      selectedId = profiles.first.id;
    }
    return ProfilesController._(
      repository: repository,
      profiles: profiles,
      selectedId: selectedId,
    );
  }

  List<TunnelProfile> get profiles => List.unmodifiable(_profiles);

  TunnelProfile? get selectedProfile {
    if (_selectedId == null) return null;
    for (final profile in _profiles) {
      if (profile.id == _selectedId) return profile;
    }
    return null;
  }

  Future<TunnelProfile> importVlessLink(String link) async {
    final profile = _parser.parse(link);
    final existingIndex = _profiles.indexWhere((item) => item.id == profile.id);
    if (existingIndex >= 0) {
      _profiles[existingIndex] = profile;
    } else {
      _profiles.insert(0, profile);
    }
    _selectedId = profile.id;
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> select(String id) async {
    if (_selectedId == id || !_profiles.any((profile) => profile.id == id)) {
      return;
    }
    _selectedId = id;
    await _repository.saveSelectedId(id);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _profiles.removeWhere((profile) => profile.id == id);
    if (_selectedId == id) {
      _selectedId = _profiles.isEmpty ? null : _profiles.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> updateLatency(String id, int? latencyMs) async {
    final index = _profiles.indexWhere((profile) => profile.id == id);
    if (index < 0) return;
    _profiles[index] = _profiles[index].copyWith(
      latencyMs: latencyMs,
      clearLatency: latencyMs == null,
    );
    await _repository.saveProfiles(_profiles);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _repository.saveProfiles(_profiles);
    await _repository.saveSelectedId(_selectedId);
  }
}
