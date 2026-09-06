import 'dart:convert';

import 'package:crypto/crypto.dart';

class SubscriptionUserInfo {
  const SubscriptionUserInfo({
    required this.uploadBytes,
    required this.downloadBytes,
    this.totalBytes,
    this.expireEpochSeconds,
  });

  final int uploadBytes;
  final int downloadBytes;
  final int? totalBytes;
  final int? expireEpochSeconds;

  int get usedBytes => uploadBytes + downloadBytes;

  int? get remainingBytes {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final remaining = total - usedBytes;
    return remaining > 0 ? remaining : 0;
  }

  double? get usageFraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (usedBytes / total).clamp(0.0, 1.0).toDouble();
  }

  DateTime? get expiresAt {
    final seconds = expireEpochSeconds;
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * Duration.millisecondsPerSecond,
      isUtc: true,
    ).toLocal();
  }

  static SubscriptionUserInfo? tryParse(String value) {
    var raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase().startsWith('base64:')) {
      final decoded = _decodeBase64Metadata(raw.substring('base64:'.length));
      if (decoded == null) return null;
      raw = decoded;
    }
    final fields = <String, int>{};
    for (final chunk in raw.split(';')) {
      final separator = chunk.indexOf('=');
      if (separator <= 0) continue;
      final key = chunk.substring(0, separator).trim().toLowerCase();
      final parsed = int.tryParse(chunk.substring(separator + 1).trim());
      if (parsed != null && parsed >= 0) fields[key] = parsed;
    }
    if (fields.isEmpty) return null;
    final upload = fields['upload'] ?? 0;
    final download = fields['download'] ?? 0;
    final total = fields['total'];
    final expire = fields['expire'];
    if (upload == 0 &&
        download == 0 &&
        (total == null || total == 0) &&
        (expire == null || expire == 0)) {
      return null;
    }
    return SubscriptionUserInfo(
      uploadBytes: upload,
      downloadBytes: download,
      totalBytes: total != null && total > 0 ? total : null,
      expireEpochSeconds: expire != null && expire > 0 ? expire : null,
    );
  }
}

String? _decodeBase64Metadata(String value) {
  try {
    var payload = value.trim().replaceAll('-', '+').replaceAll('_', '/');
    if (payload.isEmpty) return null;
    final remainder = payload.length % 4;
    if (remainder != 0) {
      payload = payload.padRight(payload.length + (4 - remainder), '=');
    }
    final decoded = utf8.decode(base64.decode(payload)).trim();
    return decoded.isEmpty ? null : decoded;
  } on Object {
    return null;
  }
}

class ProxySubscription {
  const ProxySubscription({
    required this.id,
    required this.url,
    required this.name,
    required this.profileIds,
    this.lastUpdatedEpochMs,
    this.lastMetadataCheckEpochMs,
    this.updateIntervalHours,
    this.userInfo = '',
    this.supportUrl = '',
    this.webPageUrl = '',
    this.announce = '',
    this.notices = const [],
  });

  final String id;
  final String url;
  final String name;
  final List<String> profileIds;
  final int? lastUpdatedEpochMs;
  final int? lastMetadataCheckEpochMs;
  final int? updateIntervalHours;
  final String userInfo;
  final String supportUrl;
  final String webPageUrl;
  final String announce;
  final List<String> notices;

  SubscriptionUserInfo? get parsedUserInfo => SubscriptionUserInfo.tryParse(userInfo);

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
    int? lastMetadataCheckEpochMs,
    int? updateIntervalHours,
    bool clearUpdateInterval = false,
    String? userInfo,
    String? supportUrl,
    String? webPageUrl,
    String? announce,
    List<String>? notices,
  }) {
    return ProxySubscription(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      profileIds: profileIds ?? this.profileIds,
      lastUpdatedEpochMs: lastUpdatedEpochMs ?? this.lastUpdatedEpochMs,
      lastMetadataCheckEpochMs:
          lastMetadataCheckEpochMs ?? this.lastMetadataCheckEpochMs,
      updateIntervalHours: clearUpdateInterval
          ? null
          : (updateIntervalHours ?? this.updateIntervalHours),
      userInfo: userInfo ?? this.userInfo,
      supportUrl: supportUrl ?? this.supportUrl,
      webPageUrl: webPageUrl ?? this.webPageUrl,
      announce: announce ?? this.announce,
      notices: notices ?? this.notices,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'profileIds': profileIds,
        if (lastUpdatedEpochMs != null)
          'lastUpdatedEpochMs': lastUpdatedEpochMs,
        if (lastMetadataCheckEpochMs != null)
          'lastMetadataCheckEpochMs': lastMetadataCheckEpochMs,
        if (updateIntervalHours != null)
          'updateIntervalHours': updateIntervalHours,
        if (userInfo.isNotEmpty) 'userInfo': userInfo,
        if (supportUrl.isNotEmpty) 'supportUrl': supportUrl,
        if (webPageUrl.isNotEmpty) 'webPageUrl': webPageUrl,
        if (announce.isNotEmpty) 'announce': announce,
        if (notices.isNotEmpty) 'notices': notices,
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
    final lastMetadataCheck = json['lastMetadataCheckEpochMs'];
    final interval = json['updateIntervalHours'];
    final rawNotices = json['notices'];
    final notices = rawNotices is List
        ? rawNotices
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    if (id.isEmpty || url.isEmpty) {
      throw const FormatException('Некорректная сохранённая подписка');
    }
    return ProxySubscription(
      id: id,
      url: url,
      name: name.isEmpty ? (Uri.tryParse(url)?.host ?? 'Подписка') : name,
      profileIds: List.unmodifiable(profileIds),
      lastUpdatedEpochMs: lastUpdated is num ? lastUpdated.toInt() : null,
      lastMetadataCheckEpochMs:
          lastMetadataCheck is num ? lastMetadataCheck.toInt() : null,
      updateIntervalHours:
          interval is num && interval > 0 ? interval.toInt() : null,
      userInfo: json['userInfo'] is String ? json['userInfo'] as String : '',
      supportUrl:
          json['supportUrl'] is String ? (json['supportUrl'] as String).trim() : '',
      webPageUrl:
          json['webPageUrl'] is String ? (json['webPageUrl'] as String).trim() : '',
      announce:
          json['announce'] is String ? (json['announce'] as String).trim() : '',
      notices: List.unmodifiable(notices),
    );
  }
}
