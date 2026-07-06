import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../tunnel/tunnel_models.dart';

class ProfileRepository {
  ProfileRepository(this._prefs);

  static const _profilesKey = 'orex_ray_profiles_v2';
  static const _selectedKey = 'orex_ray_selected_profile_v2';

  final SharedPreferences _prefs;

  static Future<ProfileRepository> load() async {
    return ProfileRepository(await SharedPreferences.getInstance());
  }

  List<TunnelProfile> readProfiles() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final profiles = <TunnelProfile>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          profiles.add(
            TunnelProfile.fromJson(Map<String, Object?>.from(item)),
          );
        } catch (_) {
          // A stale/corrupt profile must not prevent the app from starting.
        }
      }
      return List.unmodifiable(profiles);
    } catch (_) {
      return const [];
    }
  }

  String? readSelectedId() => _prefs.getString(_selectedKey);

  Future<void> saveProfiles(List<TunnelProfile> profiles) async {
    await _prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
  }

  Future<void> saveSelectedId(String? id) async {
    if (id == null) {
      await _prefs.remove(_selectedKey);
    } else {
      await _prefs.setString(_selectedKey, id);
    }
  }
}
