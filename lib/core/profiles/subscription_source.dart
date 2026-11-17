import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'xray_json_codec.dart';
import '../../shared/l10n/orex_l10n.dart';

class SubscriptionMetadataResult {
  const SubscriptionMetadataResult({
    this.profileTitle,
    this.userInfo,
    this.updateIntervalHours,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
  });

  final String? profileTitle;
  final String? userInfo;
  final int? updateIntervalHours;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;

  bool get isEmpty =>
      profileTitle == null &&
      userInfo == null &&
      updateIntervalHours == null &&
      supportUrl == null &&
      webPageUrl == null &&
      announce == null;
}

class SubscriptionFetchResult extends SubscriptionMetadataResult {
  const SubscriptionFetchResult({
    required this.body,
    super.profileTitle,
    super.userInfo,
    super.updateIntervalHours,
    super.supportUrl,
    super.webPageUrl,
    super.announce,
  });

  final String body;
}

class SubscriptionSource {
  SubscriptionSource({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Future<SubscriptionFetchResult> loadUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async {
    final uri = _parseUrl(value);
    final client = _createClient();
    try {
      return await _loadUrl(
        client,
        uri,
        userAgent: userAgent,
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw FormatException('Subscription download timeout'.tr);
    } on SocketException catch (error) {
      throw FormatException('Failed to load the subscription: {}'.trf([error.message]));
    } finally {
      client.close(force: true);
    }
  }

  /// Refreshes only lightweight subscription metadata. Providers that do not
  /// support HEAD simply return null; their metadata is refreshed on the next
  /// regular GET instead of downloading the whole server list on every resume.
  Future<SubscriptionMetadataResult?> loadMetadataUrl(
    String value, {
    String userAgent = 'OrexRay/Subscription',
  }) async {
    final uri = _parseUrl(value);
    final client = _createClient();
    try {
      return await _loadMetadata(
        client,
        uri,
        userAgent: userAgent,
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw FormatException('Subscription check timeout'.tr);
    } on SocketException catch (error) {
      throw FormatException('Failed to check the subscription: {}'.trf([error.message]));
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _createClient() {
    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 10);
    return client;
  }

  Uri _parseUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw FormatException('Provide the subscription URL'.tr);
    }
    if (raw.length > 8192) {
      throw FormatException('Subscription URL is too long'.tr);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('An HTTP/HTTPS subscription URL is required'.tr);
    }
    return uri;
  }

  Future<SubscriptionFetchResult> _loadUrl(
    HttpClient client,
    Uri uri, {
    required String userAgent,
  }) async {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    _configureRequest(request, userAgent);
    final response = await request.close().timeout(const Duration(seconds: 15));
    _validateResponse(response);
    final declaredLength = response.contentLength;
    if (declaredLength > XrayJsonCodec.maxPayloadBytes) {
      throw FormatException('The subscription is larger than 5 MB'.tr);
    }

    final metadata = _metadataFromHeaders(response);
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > XrayJsonCodec.maxPayloadBytes) {
        throw FormatException('The subscription is larger than 5 MB'.tr);
      }
      bytes.addAll(chunk);
    }

    String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      throw FormatException('The subscription is not UTF-8 text'.tr);
    }

    return SubscriptionFetchResult(
      body: body,
      profileTitle: metadata.profileTitle,
      userInfo: metadata.userInfo,
      updateIntervalHours: metadata.updateIntervalHours,
      supportUrl: metadata.supportUrl,
      webPageUrl: metadata.webPageUrl,
      announce: metadata.announce,
    );
  }

  Future<SubscriptionMetadataResult?> _loadMetadata(
    HttpClient client,
    Uri uri, {
    required String userAgent,
  }) async {
    final request = await client.headUrl(uri).timeout(const Duration(seconds: 8));
    _configureRequest(request, userAgent);
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode == HttpStatus.methodNotAllowed ||
        response.statusCode == HttpStatus.notImplemented) {
      await response.drain();
      return null;
    }
    _validateResponse(response);
    final metadata = _metadataFromHeaders(response);
    await response.drain();
    return metadata;
  }

  void _configureRequest(HttpClientRequest request, String userAgent) {
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/plain, application/octet-stream, */*',
    );
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set('x-device-os', _deviceOs());
    final osVersion = Platform.operatingSystemVersion.trim();
    if (osVersion.isNotEmpty) request.headers.set('x-ver-os', osVersion);
  }

  void _validateResponse(HttpClientResponse response) {
    if (_headerIsTrue(response, 'x-hwid-max-devices-reached')) {
      throw FormatException('The device limit of this subscription is exhausted'.tr);
    }
    if (_headerIsTrue(response, 'x-hwid-not-supported')) {
      throw FormatException(
        'The subscription requires a device HWID; this mode is not supported yet'.tr,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'The subscription server returned HTTP {}'.trf([response.statusCode]),
      );
    }
  }

  SubscriptionMetadataResult _metadataFromHeaders(HttpClientResponse response) {
    final rawUpdateInterval = _decodeMetadataValue(
      response.headers.value('profile-update-interval'),
    );
    final updateInterval = int.tryParse(rawUpdateInterval ?? '');
    return SubscriptionMetadataResult(
      profileTitle: _decodeMetadataValue(
        response.headers.value('profile-title'),
      ),
      userInfo: _decodeMetadataValue(
        response.headers.value('subscription-userinfo'),
      ),
      updateIntervalHours:
          updateInterval != null && updateInterval > 0 ? updateInterval : null,
      supportUrl: _normalizedUrl(response.headers.value('support-url')),
      webPageUrl:
          _normalizedUrl(response.headers.value('profile-web-page-url')),
      announce: _decodeMetadataValue(response.headers.value('announce')),
    );
  }

  String? _normalizedUrl(String? value) {
    final raw = _decodeMetadataValue(value);
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.toString();
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

  String? _decodeMetadataValue(String? value) {
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
      return null;
    }
  }
}
