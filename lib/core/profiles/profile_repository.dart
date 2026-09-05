import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tunnel/tunnel_models.dart';
import 'proxy_subscription.dart';

class ProfileRepository {
  ProfileRepository._(
    this._prefs, {
    required String? profilesPayload,
    required String? subscriptionsPayload,
    required bool secureAndroidStorage,
  })  : _profilesPayload = profilesPayload,
        _subscriptionsPayload = subscriptionsPayload,
        _secureAndroidStorage = secureAndroidStorage;

  static const _profilesKey = 'orex_ray_profiles_v2';
  static const _secureProfilesKey = 'profiles_v1';
  static const _subscriptionsKey = 'orex_ray_subscriptions_v1';
  static const _secureSubscriptionsKey = 'subscriptions_v1';
  static const _balancersKey = 'orex_ray_balancers_v1';
  static const _selectedKey = 'orex_ray_selected_target_v1';
  static const _legacySelectedKey = 'orex_ray_selected_profile_v2';
  static const _secureChannel = MethodChannel('ru.orex.ray/secure_storage');

  final SharedPreferences _prefs;
  final bool _secureAndroidStorage;
  String? _profilesPayload;
  String? _subscriptionsPayload;

  static Future<ProfileRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPayload = prefs.getString(_profilesKey);
    final legacySubscriptionsPayload = prefs.getString(_subscriptionsKey);

    if (!Platform.isAndroid) {
      return ProfileRepository._(
        prefs,
        profilesPayload: legacyPayload,
        subscriptionsPayload: legacySubscriptionsPayload,
        secureAndroidStorage: false,
      );
    }

    try {
      var securePayload = await _secureChannel.invokeMethod<String>(
        'read',
        const {'key': _secureProfilesKey},
      );
      var secureSubscriptionsPayload = await _secureChannel.invokeMethod<String>(
        'read',
        const {'key': _secureSubscriptionsKey},
      );

      if ((securePayload == null || securePayload.isEmpty) &&
          legacyPayload != null &&
          legacyPayload.isNotEmpty) {
        await _secureChannel.invokeMethod<void>(
          'write',
          {'key': _secureProfilesKey, 'value': legacyPayload},
        );
        securePayload = legacyPayload;
      }
      if ((secureSubscriptionsPayload == null ||
              secureSubscriptionsPayload.isEmpty) &&
          legacySubscriptionsPayload != null &&
          legacySubscriptionsPayload.isNotEmpty) {
        await _secureChannel.invokeMethod<void>(
          'write',
          {
            'key': _secureSubscriptionsKey,
            'value': legacySubscriptionsPayload,
          },
        );
        secureSubscriptionsPayload = legacySubscriptionsPayload;
      }

      if (securePayload != null &&
          securePayload.isNotEmpty &&
          prefs.containsKey(_profilesKey)) {
        final removed = await prefs.remove(_profilesKey);
        if (!removed && prefs.containsKey(_profilesKey)) {
          throw StateError(
            'Защищённая копия профилей существует, но старая открытая копия не удалена',
          );
        }
      }
      if (secureSubscriptionsPayload != null &&
          secureSubscriptionsPayload.isNotEmpty &&
          prefs.containsKey(_subscriptionsKey)) {
        final removed = await prefs.remove(_subscriptionsKey);
        if (!removed && prefs.containsKey(_subscriptionsKey)) {
          throw StateError(
            'Защищённая копия подписок существует, но старая открытая копия не удалена',
          );
        }
      }

      return ProfileRepository._(
        prefs,
        profilesPayload: securePayload,
        subscriptionsPayload: secureSubscriptionsPayload,
        secureAndroidStorage: true,
      );
    } on PlatformException catch (error) {
      throw StateError(
        'Не удалось открыть защищённое хранилище профилей: '
        '${error.message ?? error.code}',
      );
    }
  }

  List<TunnelProfile> readProfiles() {
    final raw = _profilesPayload;
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
        } on Object {
          // A stale/corrupt profile must not prevent the app from starting.
        }
      }
      return List.unmodifiable(profiles);
    } on Object {
      return const [];
    }
  }

  List<ProxySubscription> readSubscriptions() {
    final raw = _subscriptionsPayload;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final subscriptions = <ProxySubscription>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          subscriptions.add(
            ProxySubscription.fromJson(Map<String, Object?>.from(item)),
          );
        } on Object {
          // One stale subscription must not hide the remaining valid entries.
        }
      }
      return List.unmodifiable(subscriptions);
    } on Object {
      return const [];
    }
  }

  List<BalancerProfile> readBalancers() {
    final raw = _prefs.getString(_balancersKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final balancers = <BalancerProfile>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          balancers.add(
            BalancerProfile.fromJson(Map<String, Object?>.from(item)),
          );
        } on Object {
          // Ignore one malformed balancer instead of losing the whole list.
        }
      }
      return List.unmodifiable(balancers);
    } on Object {
      return const [];
    }
  }

  String? readSelectedId() =>
      _prefs.getString(_selectedKey) ?? _prefs.getString(_legacySelectedKey);

  Future<void> saveProfiles(List<TunnelProfile> profiles) async {
    final payload = jsonEncode(
      profiles.map((profile) => profile.toJson()).toList(),
    );
    _profilesPayload = payload;

    if (_secureAndroidStorage) {
      try {
        await _secureChannel.invokeMethod<void>(
          'write',
          {'key': _secureProfilesKey, 'value': payload},
        );
        final removed = await _prefs.remove(_profilesKey);
        if (!removed && _prefs.containsKey(_profilesKey)) {
          throw StateError(
            'Профиль сохранён защищённо, но открытая копия не была удалена',
          );
        }
        return;
      } on PlatformException catch (error) {
        throw StateError(
          'Не удалось сохранить профиль в защищённом хранилище: '
          '${error.message ?? error.code}',
        );
      }
    }

    await _prefs.setString(_profilesKey, payload);
  }

  Future<void> saveSubscriptions(List<ProxySubscription> subscriptions) async {
    final payload = jsonEncode(
      subscriptions.map((subscription) => subscription.toJson()).toList(),
    );
    _subscriptionsPayload = payload;

    if (_secureAndroidStorage) {
      try {
        await _secureChannel.invokeMethod<void>(
          'write',
          {'key': _secureSubscriptionsKey, 'value': payload},
        );
        final removed = await _prefs.remove(_subscriptionsKey);
        if (!removed && _prefs.containsKey(_subscriptionsKey)) {
          throw StateError(
            'Подписки сохранены защищённо, но открытая копия не была удалена',
          );
        }
        return;
      } on PlatformException catch (error) {
        throw StateError(
          'Не удалось сохранить подписки в защищённом хранилище: '
          '${error.message ?? error.code}',
        );
      }
    }

    await _prefs.setString(_subscriptionsKey, payload);
  }

  Future<void> saveBalancers(List<BalancerProfile> balancers) async {
    await _prefs.setString(
      _balancersKey,
      jsonEncode(balancers.map((item) => item.toJson()).toList()),
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
