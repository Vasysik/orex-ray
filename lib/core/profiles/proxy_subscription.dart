import 'dart:convert';

import 'package:crypto/crypto.dart';

class ProxySubscription {
  const ProxySubscription({
    required this.id,
    required this.url,
    required this.name,
    required this.profileIds,
    this.lastUpdatedEpochMs,
    this.updateIntervalHours,
    this.userInfo = '',
  });

  final String id;
  final String url;
  final String name;
  final List<String> profileIds;
  final int? lastUpdatedEpochMs;
  final int? updateIntervalHours;
  final String userInfo;

  static String idForUrl(String value) {
    final normalized = value.trim();
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'sub-${digest.substring(0, 24)}';
  }

  ProxySubscription copyWith({
    String? id,
    String? url,
    String? name,
    List<String>? profileIds,
    int? lastUpdatedEpochMs,
    int? updateIntervalHours,
    bool clearUpdateInterval = false,
    String? userInfo,
  }) {
    return ProxySubscription(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      profileIds: profileIds ?? this.profileIds,
      lastUpdatedEpochMs: lastUpdatedEpochMs ?? this.lastUpdatedEpochMs,
      updateIntervalHours: clearUpdateInterval
          ? null
          : (updateIntervalHours ?? this.updateIntervalHours),
      userInfo: userInfo ?? this.userInfo,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'profileIds': profileIds,
        if (lastUpdatedEpochMs != null)
          'lastUpdatedEpochMs': lastUpdatedEpochMs,
        if (updateIntervalHours != null)
          'updateIntervalHours': updateIntervalHours,
        if (userInfo.isNotEmpty) 'userInfo': userInfo,
      };

  factory ProxySubscription.fromJson(Map<String, Object?> json) {
    final id = json['id'] is String ? (json['id'] as String).trim() : '';
    final url = json['url'] is String ? (json['url'] as String).trim() : '';
    final name = json['name'] is String ? (json['name'] as String).trim() : '';
    final rawProfileIds = json['profileIds'];
    final profileIds = rawProfileIds is List
        ? rawProfileIds.whereType<String>().where((id) => id.isNotEmpty).toList()
        : <String>[];
    final lastUpdated = json['lastUpdatedEpochMs'];
    final interval = json['updateIntervalHours'];
    if (id.isEmpty || url.isEmpty) {
      throw const FormatException('Некорректная сохранённая подписка');
    }
    return ProxySubscription(
      id: id,
      url: url,
      name: name.isEmpty
          ? (Uri.tryParse(url)?.host ?? 'Подписка')
          : name,
      profileIds: List.unmodifiable(profileIds),
      lastUpdatedEpochMs: lastUpdated is num ? lastUpdated.toInt() : null,
      updateIntervalHours:
          interval is num && interval > 0 ? interval.toInt() : null,
      userInfo: json['userInfo'] is String ? json['userInfo'] as String : '',
    );
  }
}
