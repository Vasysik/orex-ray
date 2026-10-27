import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';

/// Only enable this in local test builds. It does not fabricate a GitHub release.
/// flutter run --profile --dart-define=OREXRAY_UPDATE_TEST_SAME_VERSION=true
const bool orexrayUpdateTestSameVersion = bool.fromEnvironment(
  'OREXRAY_UPDATE_TEST_SAME_VERSION', defaultValue: false,
);

const _releasesApi = 'https://api.github.com/repos/Vasysik/orex-ray/releases?per_page=30';
const _dismissKey = 'orexray_update_dismissed_release_v1';

class OrexRayRelease {
  const OrexRayRelease({
    required this.version,
    required this.build,
    required this.assetName,
    required this.assetUri,
    required this.assetBytes,
    required this.checksumUri,
    required this.notes,
    required this.htmlUri,
  });

  final String version;
  final int build;
  final String assetName;
  final Uri assetUri;
  final int assetBytes;
  final Uri checksumUri;
  final String notes;
  final Uri htmlUri;
  String get tag => '$version+$build';

  static final RegExp tagPattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)\+(\d+)$');

  static int? compareVersions(String a, String b) {
    final ma = tagPattern.firstMatch(a);
    final mb = tagPattern.firstMatch(b);
    if (ma == null || mb == null) return null;
    for (var i = 1; i <= 4; i++) {
      final x = int.parse(ma.group(i)!);
      final y = int.parse(mb.group(i)!);
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static bool shouldOffer(String candidate, String installed, {bool allowSame = false}) {
    final result = compareVersions(candidate, installed);
    return result != null && (result > 0 || (result == 0 && allowSame));
  }

  static OrexRayRelease? parse(Map<String, dynamic> json, String suffix) {
    if (json['draft'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String || tagPattern.firstMatch(tag) == null) return null;
    final match = tagPattern.firstMatch(tag)!;
    final version = '${match[1]}.${match[2]}.${match[3]}';
    final build = int.parse(match[4]!);
    if (build < 1) return null;
    final expected = 'OrexRay-$version+$build-$suffix';
    final assets = json['assets'];
    if (assets is! List) return null;
    Map<String, dynamic>? installer;
    Map<String, dynamic>? checksum;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final a = Map<String, dynamic>.from(asset);
      if (a['name'] == expected) installer = a;
      if (a['name'] == 'SHA256SUMS.txt') checksum = a;
    }
    if (installer == null || checksum == null) return null;
    final uri = Uri.tryParse(installer['browser_download_url']?.toString() ?? '');
    final shaUri = Uri.tryParse(checksum['browser_download_url']?.toString() ?? '');
    if (uri == null || shaUri == null ||
        !_trustedReleaseLink(uri, tag) || !_trustedReleaseLink(shaUri, tag) ||
        uri.pathSegments.last != expected ||
        shaUri.pathSegments.last != 'SHA256SUMS.txt') {
      return null;
    }
    final size = installer['size'];
    if (size is! int || size <= 0 || size > 1024 * 1024 * 1024) return null;
    final html = Uri.tryParse(json['html_url']?.toString() ?? '');
    return OrexRayRelease(
      version: version,
      build: build,
      assetName: expected,
      assetUri: uri,
      assetBytes: size,
      checksumUri: shaUri,
      notes: (json['body'] is String && (json['body'] as String).trim().isNotEmpty)
          ? (json['body'] as String).trim() : 'Описание изменений не добавлено.',
      htmlUri: html != null && html.scheme == 'https' &&
          html.host == 'github.com' &&
          html.pathSegments.length >= 3 &&
          html.pathSegments[0] == 'Vasysik' &&
          html.pathSegments[1] == 'orex-ray'
          ? html : Uri.parse('https://github.com/Vasysik/orex-ray/releases'),
    );
  }

  static bool _trustedReleaseLink(Uri uri, String tag) {
    if (uri.scheme != 'https' || uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return false;
    }
    final segments = uri.pathSegments;
    return segments.length == 6 &&
        segments[0] == 'Vasysik' && segments[1] == 'orex-ray' &&
        segments[2] == 'releases' && segments[3] == 'download' &&
        segments[4] == tag && segments[5].isNotEmpty;
  }
}

class OrexRayUpdateCancelled implements Exception {
  const OrexRayUpdateCancelled();
}

class OrexRayUpdateToken {
  bool _cancelled = false;
  void Function()? _cancelRequest;
  bool get isCancelled => _cancelled;
  void bind(void Function() stop) { _cancelRequest = stop; if (_cancelled) stop(); }
  void cancel() { _cancelled = true; _cancelRequest?.call(); }
  void check() { if (_cancelled) throw const OrexRayUpdateCancelled(); }
}

enum OrexRayUpdateState { idle, checking, upToDate, available, error }

class OrexRayUpdates extends ChangeNotifier {
  OrexRayUpdates._(this.current, this._prefs);

  final OrexAppVersion current;
  final SharedPreferences _prefs;
  static const MethodChannel _android = MethodChannel('ru.orex.ray/app_update');
  OrexRayUpdateState state = OrexRayUpdateState.idle;
  OrexRayRelease? available;
  String? error;
  String? _dismissed;
  bool _disposed = false;

  static Future<OrexRayUpdates> create(OrexAppVersion current) async {
    final prefs = await SharedPreferences.getInstance();
    return OrexRayUpdates._(current, prefs).._dismissed = prefs.getString(_dismissKey);
  }

  bool get supportsInstall => Platform.isAndroid || Platform.isWindows;
  bool get showBanner => available != null && available!.tag != _dismissed;
  void _notify() { if (!_disposed) notifyListeners(); }

  Future<void> dismiss() async {
    final release = available;
    if (release == null) return;
    _dismissed = release.tag;
    _notify();
    await _prefs.setString(_dismissKey, release.tag);
  }

  Future<void> check() async {
    if (state == OrexRayUpdateState.checking) return;
    if (!supportsInstall) return;
    state = OrexRayUpdateState.checking;
    error = null;
    _notify();
    try {
      final suffix = await _artifactSuffix();
      final bytes = await _readSmall(Uri.parse(_releasesApi), 512 * 1024);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) throw const FormatException('Некорректный ответ GitHub');
      OrexRayRelease? newest;
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final release = OrexRayRelease.parse(Map<String, dynamic>.from(raw), suffix);
        if (release == null) continue;
        if (!OrexRayRelease.shouldOffer(
          release.tag, current.label, allowSame: orexrayUpdateTestSameVersion,
        )) {
          continue;
        }
        if (newest == null ||
            OrexRayRelease.compareVersions(release.tag, newest.tag)! > 0) {
          newest = release;
        }
      }
      available = newest;
      state = newest == null ? OrexRayUpdateState.upToDate : OrexRayUpdateState.available;
    } catch (e) {
      error = e is SocketException ? 'Нет доступа к GitHub' :
          e is TimeoutException ? 'GitHub не ответил вовремя' :
          e is FormatException ? e.message : 'Не удалось проверить GitHub Releases';
      state = OrexRayUpdateState.error;
    }
    _notify();
  }

  Future<String> _artifactSuffix() async {
    if (Platform.isWindows) return 'x64-setup.exe';
    if (Platform.isAndroid) {
      final abi = await _android.invokeMethod<String>('getPrimaryAbi');
      if (abi == 'arm64-v8a' || abi == 'armeabi-v7a' || abi == 'x86_64') {
        return '$abi.apk';
      }
    }
    throw const FormatException('Архитектура устройства не поддерживается');
  }

  Future<List<int>> _readSmall(Uri uri, int limit) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final response = await _request(client, uri).timeout(const Duration(seconds: 18));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 18))) {
        bytes += chunk.length;
        if (bytes > limit) throw const FormatException('Ответ GitHub слишком большой');
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static bool _allowedRequestHost(Uri url) =>
      url.scheme == 'https' && url.userInfo.isEmpty &&
      (url.host == 'api.github.com' || url.host == 'github.com' ||
       url.host == 'release-assets.githubusercontent.com' ||
       url.host == 'objects.githubusercontent.com');

  Future<HttpClientResponse> _request(HttpClient client, Uri uri) async {
    var next = uri;
    for (var i = 0; i < 6; i++) {
      if (!_allowedRequestHost(next)) throw const FormatException('Недоверенный адрес загрузки');
      final request = await client.getUrl(next);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'OrexRay-Updater/0.7');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.isRedirect) {
        final target = response.headers.value(HttpHeaders.locationHeader);
        if (target == null) throw const FormatException('Редирект GitHub без адреса');
        final resolved = next.resolve(target);
        if (!_allowedRequestHost(resolved)) {
          throw const FormatException('Недоверенный редирект обновления');
        }
        await response.drain<void>();
        next = resolved;
        continue;
      }
      return response;
    }
    throw const FormatException('Слишком много редиректов GitHub');
  }

  Future<String> download(
    OrexRayUpdateToken token,
    void Function(int received, int total) onProgress,
  ) async {
    final release = available;
    if (release == null) throw StateError('Нет доступного обновления');
    token.check();
    final sums = utf8.decode(await _readSmall(release.checksumUri, 64 * 1024));
    final expected = _checksumFor(sums, release.assetName);
    if (expected == null) {
      throw const FormatException('В GitHub Release нет SHA-256 для установщика');
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}orexray-updates');
    await dir.create(recursive: true);
    final result = File('${dir.path}${Platform.pathSeparator}${release.assetName}');
    final part = File('${result.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    token.bind(() => client.close(force: true));
    IOSink? sink;
    try {
      if (await part.exists()) await part.delete();
      final response = await _request(client, release.assetUri).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      if (response.contentLength >= 0 && response.contentLength != release.assetBytes) {
        throw const FormatException('Размер установщика не совпадает с GitHub');
      }
      sink = part.openWrite();
      var received = 0;
      onProgress(0, release.assetBytes);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        token.check();
        received += chunk.length;
        if (received > release.assetBytes) throw const FormatException('Слишком большой установщик');
        sink.add(chunk);
        onProgress(received, release.assetBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      token.check();
      if (received != release.assetBytes) throw const FormatException('Установщик загружен не полностью');
      final actual = (await sha256.bind(part.openRead()).first).toString();
      if (actual.toLowerCase() != expected) throw const FormatException('SHA-256 установщика не совпал');
      token.check();
      if (await result.exists()) await result.delete();
      await part.rename(result.path);
      return result.path;
    } catch (_) {
      try { await sink?.close(); } catch (_) { /* cleanup */ }
      if (await part.exists()) await part.delete();
      if (token.isCancelled) throw const OrexRayUpdateCancelled();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static String? _checksumFor(String file, String asset) {
    for (final line in const LineSplitter().convert(file)) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(\S+)$').firstMatch(line.trim());
      if (match != null && match[2] == asset) return match[1]!.toLowerCase();
    }
    return null;
  }

  Future<bool> launchInstaller(String path) async {
    if (Platform.isAndroid) {
      final status = await _android.invokeMethod<String>('installApk', {'path': path});
      return status == 'permission_required';
    }
    if (Platform.isWindows) {
      // Inno Setup requests elevation; CreateProcess alone fails with error 740.
      final escaped = path.replaceAll("'", "''");
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-Command',
        "Start-Process -FilePath '$escaped' -Verb RunAs",
      ]);
      if (result.exitCode != 0) throw StateError('Не удалось запустить установщик: ${result.stderr}');
      return false;
    }
    throw UnsupportedError('Обновления доступны только на Android и Windows');
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
