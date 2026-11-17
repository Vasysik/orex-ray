import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'xray_json_codec.dart';
import '../../shared/l10n/orex_l10n.dart';

class XrayJsonSource {
  XrayJsonSource({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Future<String> loadUrl(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw FormatException('Provide the JSON URL'.tr);
    }
    if (raw.length > 8192) {
      throw FormatException('JSON URL is too long'.tr);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('An HTTP/HTTPS URL with JSON is required'.tr);
    }

    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 10);
    try {
      // This timeout wraps DNS/connect/headers/body as one operation, rather
      // than allowing each stage timeout to accumulate into a much longer wait.
      return await _loadUrl(client, uri).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw FormatException('JSON download timeout'.tr);
    } on SocketException catch (error) {
      throw FormatException('Failed to load JSON: {}'.trf([error.message]));
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _loadUrl(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri).timeout(
          const Duration(seconds: 12),
        );
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/json, */*',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'OrexRay/Xray-JSON');
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'The JSON server returned HTTP {}'.trf([response.statusCode]),
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength > XrayJsonCodec.maxPayloadBytes) {
      throw FormatException('Xray JSON is larger than 5 MB'.tr);
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > XrayJsonCodec.maxPayloadBytes) {
        throw FormatException('Xray JSON is larger than 5 MB'.tr);
      }
      bytes.addAll(chunk);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw FormatException('JSON at URL is not UTF-8 text'.tr);
    }
  }
}
