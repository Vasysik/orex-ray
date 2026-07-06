import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeoAssetStatus {
  const GeoAssetStatus({
    required this.name,
    required this.fileName,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.installed = false,
  });

  final String name;
  final String fileName;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final bool installed;
}

class GeoDataController extends ChangeNotifier {
  GeoDataController._({
    required SharedPreferences preferences,
    required Directory directory,
    required bool autoUpdate,
    required int updateIntervalHours,
    required DateTime? lastCheckedAt,
  })  : _preferences = preferences,
        _directory = directory,
        _autoUpdate = autoUpdate,
        _updateIntervalHours = updateIntervalHours,
        _lastCheckedAt = lastCheckedAt;

  static const _channel = MethodChannel('ru.orex.ray/tunnel');
  static const _autoUpdateKey = 'orex_ray_geodata_auto_update_v1';
  static const _intervalKey = 'orex_ray_geodata_interval_hours_v1';
  static const _lastCheckedKey = 'orex_ray_geodata_last_checked_v1';

  static const _releaseBase =
      'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release';

  final SharedPreferences _preferences;
  final Directory _directory;

  bool _autoUpdate;
  int _updateIntervalHours;
  DateTime? _lastCheckedAt;
  List<GeoAssetStatus> _assets = const [];
  bool _updating = false;
  double _progress = 0;
  String? _message;
  String? _error;

  static Future<GeoDataController> load({Directory? directoryOverride}) async {
    final preferences = await SharedPreferences.getInstance();
    final directory = directoryOverride ?? await _resolveDirectory();
    await directory.create(recursive: true);
    final rawLastChecked = preferences.getString(_lastCheckedKey);
    final controller = GeoDataController._(
      preferences: preferences,
      directory: directory,
      autoUpdate: preferences.getBool(_autoUpdateKey) ?? true,
      updateIntervalHours: _validInterval(
            preferences.getInt(_intervalKey),
          ) ??
          24,
      lastCheckedAt:
          rawLastChecked == null ? null : DateTime.tryParse(rawLastChecked),
    );
    await controller.refreshStatus();
    return controller;
  }

  bool get autoUpdate => _autoUpdate;
  int get updateIntervalHours => _updateIntervalHours;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  List<GeoAssetStatus> get assets => List.unmodifiable(_assets);
  bool get updating => _updating;
  double get progress => _progress;
  String? get message => _message;
  String? get error => _error;
  String get directoryPath => _directory.path;

  Future<void> setAutoUpdate(bool value) async {
    if (_autoUpdate == value) return;
    _autoUpdate = value;
    await _preferences.setBool(_autoUpdateKey, value);
    notifyListeners();
  }

  Future<void> setUpdateIntervalHours(int value) async {
    final normalized = _validInterval(value);
    if (normalized == null) {
      throw const FormatException('Интервал должен быть 12, 24, 72 или 168 часов');
    }
    if (_updateIntervalHours == normalized) return;
    _updateIntervalHours = normalized;
    await _preferences.setInt(_intervalKey, normalized);
    notifyListeners();
  }

  Future<void> maybeAutoUpdate() async {
    if (!_autoUpdate || _updating) return;
    final last = _lastCheckedAt;
    if (last != null &&
        DateTime.now().difference(last) <
            Duration(hours: _updateIntervalHours)) {
      return;
    }
    await updateNow(silent: true);
  }

  Future<void> refreshStatus() async {
    final statuses = <GeoAssetStatus>[];
    for (final item in const [
      ('GeoIP', 'geoip.dat'),
      ('GeoSite', 'geosite.dat'),
    ]) {
      final file = File(p.join(_directory.path, item.$2));
      if (await file.exists()) {
        final stat = await file.stat();
        statuses.add(GeoAssetStatus(
          name: item.$1,
          fileName: item.$2,
          installed: true,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
      } else {
        statuses.add(GeoAssetStatus(name: item.$1, fileName: item.$2));
      }
    }
    _assets = statuses;
    notifyListeners();
  }

  Future<void> updateNow({bool silent = false}) async {
    if (_updating) return;
    _updating = true;
    _progress = 0;
    _error = null;
    _message = silent ? null : 'Проверяем GeoData…';
    notifyListeners();

    final client = HttpClient()..userAgent = 'OrexRay/0.6.0';
    try {
      const files = ['geoip.dat', 'geosite.dat'];
      for (var index = 0; index < files.length; index++) {
        final fileName = files[index];
        _message = 'Обновляем $fileName…';
        _progress = index / files.length;
        notifyListeners();
        await _downloadVerified(client, fileName, index, files.length);
      }
      _lastCheckedAt = DateTime.now();
      await _preferences.setString(
        _lastCheckedKey,
        _lastCheckedAt!.toIso8601String(),
      );
      _message = 'GeoData обновлена. Новые данные применятся при следующем подключении.';
      _progress = 1;
      await refreshStatus();
    } on Object catch (error) {
      _error = _friendlyError(error);
      _message = null;
    } finally {
      client.close(force: true);
      _updating = false;
      notifyListeners();
    }
  }

  Future<void> _downloadVerified(
    HttpClient client,
    String fileName,
    int fileIndex,
    int fileCount,
  ) async {
    final expectedHash = await _downloadText(
      client,
      Uri.parse('$_releaseBase/$fileName.sha256sum'),
    ).then(_parseSha256);

    final uri = Uri.parse('$_releaseBase/$fileName');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Сервер вернул HTTP ${response.statusCode} для $fileName',
        uri: uri,
      );
    }

    final temp = File(p.join(_directory.path, '.$fileName.download'));
    final sink = temp.openWrite();
    final total = response.contentLength;
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _progress = (fileIndex + (received / total)) / fileCount;
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }

    final actualHash = await sha256.bind(temp.openRead()).first;
    final actual = actualHash.toString().toLowerCase();
    if (actual != expectedHash) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // The checksum failure is the important error; temp cleanup is best effort.
      }
      throw StateError('SHA-256 не совпал для $fileName');
    }

    final destination = File(p.join(_directory.path, fileName));
    final backup = File('${destination.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await destination.exists()) await destination.rename(backup.path);
    try {
      await temp.rename(destination.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<String> _downloadText(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return utf8.decoder.bind(response).join();
  }

  String _parseSha256(String value) {
    final token = value.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Некорректная контрольная сумма GeoData');
    }
    return token;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('HttpException')) {
      return 'Не удалось скачать GeoData. Проверь интернет и попробуй снова.';
    }
    return text.replaceFirst('Bad state: ', '').replaceFirst('FormatException: ', '');
  }

  static Future<Directory> _resolveDirectory() async {
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('assetDirectory');
        if (path != null && path.trim().isNotEmpty) return Directory(path);
      } catch (_) {
        // Fall back to the standard app support directory.
      }
    }
    final support = await getApplicationSupportDirectory();
    if (Platform.isWindows) return Directory(p.join(support.path, 'xray-core'));
    return Directory(p.join(support.path, 'xray'));
  }

  static int? _validInterval(int? value) =>
      const {12, 24, 72, 168}.contains(value) ? value : null;
}
