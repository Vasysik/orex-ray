import 'dart:convert';

import '../tunnel/tunnel_models.dart';
import 'proxy_link_parser.dart';
import 'xray_json_codec.dart';

class SubscriptionParseResult {
  const SubscriptionParseResult({
    required this.profiles,
    required this.skippedUnsupported,
    this.profileTitle,
    this.userInfo,
    this.updateIntervalHours,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
    this.notices = const [],
  });

  final List<TunnelProfile> profiles;
  final int skippedUnsupported;
  final String? profileTitle;
  final String? userInfo;
  final int? updateIntervalHours;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;
  final List<String> notices;
}

class SubscriptionParser {
  const SubscriptionParser();

  static const _supportedSchemes = <String>{
    'vless',
    'vmess',
    'trojan',
    'ss',
    'socks',
    'socks5',
    'http',
    'https',
  };

  SubscriptionParseResult parse(String input) {
    return _parse(input, allowBase64: true);
  }

  SubscriptionParseResult _parse(
    String input, {
    required bool allowBase64,
  }) {
    var text = input.trim();
    if (text.startsWith('\uFEFF')) text = text.substring(1).trimLeft();
    if (text.isEmpty) {
      throw const FormatException('Подписка пустая');
    }

    final metadata = _extractMetadata(text);
    text = metadata.body.trim();
    if (text.isEmpty) {
      throw const FormatException('В подписке нет серверов');
    }

    final jsonResult = _tryJson(text);
    if (jsonResult != null && jsonResult.profiles.isNotEmpty) {
      return SubscriptionParseResult(
        profiles: jsonResult.profiles,
        skippedUnsupported: jsonResult.skippedUnsupported,
        profileTitle: metadata.profileTitle,
        userInfo: metadata.userInfo,
        updateIntervalHours: metadata.updateIntervalHours,
        supportUrl: metadata.supportUrl ?? jsonResult.supportUrl,
        webPageUrl: metadata.webPageUrl ?? jsonResult.webPageUrl,
        announce: metadata.announce ?? jsonResult.announce,
        notices: jsonResult.notices,
      );
    }

    final linkResult = _parseLinks(text);
    if (linkResult.profiles.isNotEmpty) {
      return SubscriptionParseResult(
        profiles: linkResult.profiles,
        skippedUnsupported: linkResult.skippedUnsupported,
        profileTitle: metadata.profileTitle,
        userInfo: metadata.userInfo,
        updateIntervalHours: metadata.updateIntervalHours,
        supportUrl: metadata.supportUrl ?? linkResult.supportUrl,
        webPageUrl: metadata.webPageUrl ?? linkResult.webPageUrl,
        announce: metadata.announce ?? linkResult.announce,
        notices: linkResult.notices,
      );
    }

    if (allowBase64) {
      final decoded = _tryDecodeBase64(text);
      if (decoded != null && decoded.trim() != text) {
        final nested = _parse(decoded, allowBase64: false);
        return SubscriptionParseResult(
          profiles: nested.profiles,
          skippedUnsupported: nested.skippedUnsupported,
          profileTitle: metadata.profileTitle ?? nested.profileTitle,
          userInfo: metadata.userInfo ?? nested.userInfo,
          updateIntervalHours:
              metadata.updateIntervalHours ?? nested.updateIntervalHours,
          supportUrl: metadata.supportUrl ?? nested.supportUrl,
          webPageUrl: metadata.webPageUrl ?? nested.webPageUrl,
          announce: metadata.announce ?? nested.announce,
          notices: nested.notices,
        );
      }
    }

    throw const FormatException(
      'В подписке не найдено поддерживаемых серверов',
    );
  }

  SubscriptionParseResult? _tryJson(String text) {
    Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return null;
    }

    if (root is String) {
      final inner = root.trim();
      if (inner.isEmpty) return null;
      try {
        return _parse(inner, allowBase64: true);
      } on FormatException {
        return null;
      }
    }

    if (root is List && root.any((item) => item is String)) {
      final strings = root.whereType<String>().join('\n');
      final links = _parseLinks(strings);
      if (links.profiles.isNotEmpty) return links;
    }

    try {
      final decoded = const XrayJsonCodec().decode(text);
      if (decoded.profiles.isEmpty) return null;
      return _filterInformationalProfiles(
        decoded.profiles,
        skippedUnsupported: decoded.skippedUnsupported,
      );
    } on FormatException {
      return null;
    }
  }

  SubscriptionParseResult _parseLinks(String text) {
    final parser = const ProxyLinkParser();
    final profiles = <TunnelProfile>[];
    final notices = <String>[];
    final seenIds = <String>{};
    final seenNotices = <String>{};
    String? legacySupportUrl;
    var skipped = 0;

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('://');
      final scheme = separator > 0
          ? line.substring(0, separator).trim().toLowerCase()
          : '';
      if (!_supportedSchemes.contains(scheme)) {
        skipped += 1;
        continue;
      }
      try {
        final profile = parser.parse(line);
        if (_isInformationalProfile(profile)) {
          final notice = profile.name.trim();
          if (notice.isNotEmpty && seenNotices.add(notice)) notices.add(notice);
          legacySupportUrl ??= _supportUrlFromNotice(notice);
          continue;
        }
        if (seenIds.add(profile.id)) profiles.add(profile);
      } on Object {
        skipped += 1;
      }
    }

    return SubscriptionParseResult(
      profiles: List.unmodifiable(profiles),
      skippedUnsupported: skipped,
      supportUrl: legacySupportUrl,
      notices: List.unmodifiable(notices),
    );
  }

  SubscriptionParseResult _filterInformationalProfiles(
    Iterable<TunnelProfile> source, {
    required int skippedUnsupported,
  }) {
    final profiles = <TunnelProfile>[];
    final notices = <String>[];
    final seenNotices = <String>{};
    String? legacySupportUrl;
    for (final profile in source) {
      if (_isInformationalProfile(profile)) {
        final notice = profile.name.trim();
        if (notice.isNotEmpty && seenNotices.add(notice)) notices.add(notice);
        legacySupportUrl ??= _supportUrlFromNotice(notice);
      } else {
        profiles.add(profile);
      }
    }
    return SubscriptionParseResult(
      profiles: List.unmodifiable(profiles),
      skippedUnsupported: skippedUnsupported,
      supportUrl: legacySupportUrl,
      notices: List.unmodifiable(notices),
    );
  }

  bool _isInformationalProfile(TunnelProfile profile) {
    final address = profile.address.trim().toLowerCase();
    if (address == 'localhost' || address == '::1' || address == '[::1]') {
      return true;
    }
    return RegExp(r'^127(?:\.\d{1,3}){3}$').hasMatch(address);
  }

  String? _tryDecodeBase64(String text) {
    var compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || !RegExp(r'^[A-Za-z0-9_+/=-]+$').hasMatch(compact)) {
      return null;
    }
    try {
      compact = compact.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = compact.length % 4;
      if (remainder != 0) {
        compact = compact.padRight(compact.length + (4 - remainder), '=');
      }
      final decoded = utf8.decode(base64.decode(compact));
      if (!decoded.contains('://') &&
          !decoded.trimLeft().startsWith('{') &&
          !decoded.trimLeft().startsWith('[')) {
        return null;
      }
      return decoded;
    } on Object {
      return null;
    }
  }

  _SubscriptionMetadata _extractMetadata(String text) {
    final body = <String>[];
    String? title;
    String? userInfo;
    int? updateInterval;
    String? supportUrl;
    String? webPageUrl;
    String? announce;

    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#')) {
        body.add(line);
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon <= 1) continue;
      final key = trimmed.substring(1, colon).trim().toLowerCase();
      final value = trimmed.substring(colon + 1).trim();
      switch (key) {
        case 'profile-title':
          title = _decodeMetadataTitle(value);
          break;
        case 'subscription-userinfo':
          if (value.isNotEmpty) userInfo = value;
          break;
        case 'profile-update-interval':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed > 0) updateInterval = parsed;
          break;
        case 'support-url':
          supportUrl = _normalizedMetadataUrl(value);
          break;
        case 'profile-web-page-url':
          webPageUrl = _normalizedMetadataUrl(value);
          break;
        case 'announce':
          if (value.isNotEmpty) announce = value;
          break;
      }
    }

    return _SubscriptionMetadata(
      body: body.join('\n'),
      profileTitle: title,
      userInfo: userInfo,
      updateIntervalHours: updateInterval,
      supportUrl: supportUrl,
      webPageUrl: webPageUrl,
      announce: announce,
    );
  }

  String? _supportUrlFromNotice(String value) {
    final match = RegExp(
      r'(?:https?://)?(?:www\.)?t\.me/[A-Za-z0-9_+\-/]+',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final raw = match.group(0)!;
    return raw.startsWith('http') ? raw : 'https://$raw';
  }

  String? _normalizedMetadataUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.toString();
  }

  String? _decodeMetadataTitle(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (!raw.toLowerCase().startsWith('base64:')) return raw;
    try {
      var encoded = raw.substring('base64:'.length).trim();
      encoded = encoded.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = encoded.length % 4;
      if (remainder != 0) {
        encoded = encoded.padRight(encoded.length + (4 - remainder), '=');
      }
      final decoded = utf8.decode(base64.decode(encoded)).trim();
      return decoded.isEmpty ? null : decoded;
    } on Object {
      return raw;
    }
  }
}

class _SubscriptionMetadata {
  const _SubscriptionMetadata({
    required this.body,
    this.profileTitle,
    this.userInfo,
    this.updateIntervalHours,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
  });

  final String body;
  final String? profileTitle;
  final String? userInfo;
  final int? updateIntervalHours;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;
}
