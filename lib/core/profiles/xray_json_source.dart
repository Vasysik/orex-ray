import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'xray_json_codec.dart';

class XrayJsonSource {
  XrayJsonSource({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  Future<String> loadUrl(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw const FormatException('Укажи URL JSON');
    }
    if (raw.length > 8192) {
      throw const FormatException('URL JSON слишком длинный');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Нужен HTTP/HTTPS URL с JSON');
    }

    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 10);
    try {
      // This timeout wraps DNS/connect/headers/body as one operation, rather
      // than allowing each stage timeout to accumulate into a much longer wait.
      return await _loadUrl(client, uri).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const FormatException('Таймаут загрузки JSON');
    } on SocketException catch (error) {
      throw FormatException('Не удалось загрузить JSON: ${error.message}');
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
        'Сервер JSON вернул HTTP ${response.statusCode}',
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength > XrayJsonCodec.maxPayloadBytes) {
      throw const FormatException('JSON Xray больше 5 МБ');
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > XrayJsonCodec.maxPayloadBytes) {
        throw const FormatException('JSON Xray больше 5 МБ');
      }
      bytes.addAll(chunk);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('JSON по URL не является UTF-8 текстом');
    }
  }
}
