import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'xray_json_codec.dart';

class SubscriptionFetchResult {
  const SubscriptionFetchResult({
    required this.body,
    this.profileTitle,
    this.userInfo,
    this.updateIntervalHours,
  });

  final String body;
  final String? profileTitle;
  final String? userInfo;
  final int? updateIntervalHours;
}

class SubscriptionSource {
  SubscriptionSource({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Future<SubscriptionFetchResult> loadUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw const FormatException('Укажи URL подписки');
    }
    if (raw.length > 8192) {
      throw const FormatException('URL подписки слишком длинный');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Нужен HTTP/HTTPS URL подписки');
    }

    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 10);
    try {
      return await _loadUrl(
        client,
        uri,
        userAgent: userAgent,
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const FormatException('Таймаут загрузки подписки');
    } on SocketException catch (error) {
      throw FormatException('Не удалось загрузить подписку: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<SubscriptionFetchResult> _loadUrl(
    HttpClient client,
    Uri uri, {
    required String userAgent,
  }) async {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/plain, application/octet-stream, */*',
    );
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set('x-device-os', _deviceOs());
    final osVersion = Platform.operatingSystemVersion.trim();
    if (osVersion.isNotEmpty) request.headers.set('x-ver-os', osVersion);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (_headerIsTrue(response, 'x-hwid-max-devices-reached')) {
      throw const FormatException(
        'Лимит устройств этой подписки исчерпан',
      );
    }
    if (_headerIsTrue(response, 'x-hwid-not-supported')) {
      throw const FormatException(
        'Подписка требует HWID устройства; такой режим пока не поддерживается',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Сервер подписки вернул HTTP ${response.statusCode}',
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength > XrayJsonCodec.maxPayloadBytes) {
      throw const FormatException('Подписка больше 5 МБ');
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > XrayJsonCodec.maxPayloadBytes) {
        throw const FormatException('Подписка больше 5 МБ');
      }
      bytes.addAll(chunk);
    }

    String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('Подписка не является UTF-8 текстом');
    }

    final profileTitle = _decodeTitle(
      response.headers.value('profile-title'),
    );
    final userInfo = response.headers.value('subscription-userinfo')?.trim();
    final updateInterval = int.tryParse(
      response.headers.value('profile-update-interval')?.trim() ?? '',
    );
    return SubscriptionFetchResult(
      body: body,
      profileTitle: profileTitle,
      userInfo: userInfo == null || userInfo.isEmpty ? null : userInfo,
      updateIntervalHours:
          updateInterval != null && updateInterval > 0 ? updateInterval : null,
    );
  }

  bool _headerIsTrue(HttpClientResponse response, String name) {
    return response.headers.value(name)?.trim().toLowerCase() == 'true';
  }

  String _deviceOs() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  String? _decodeTitle(String? value) {
    if (value == null) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (!raw.toLowerCase().startsWith('base64:')) return raw;
    try {
      var payload = raw.substring('base64:'.length).trim();
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = payload.length % 4;
      if (remainder != 0) {
        payload = payload.padRight(payload.length + (4 - remainder), '=');
      }
      final decoded = utf8.decode(base64.decode(payload)).trim();
      return decoded.isEmpty ? null : decoded;
    } on Object {
      return raw;
    }
  }
}
