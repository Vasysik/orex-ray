import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_version.dart';

class XrayCoreInstall {
  const XrayCoreInstall({
    required this.directory,
    required this.executable,
    required this.assetDirectory,
    required this.elevatedAssetDirectory,
  });

  final Directory directory;
  final File executable;
  final Directory assetDirectory;
  final Directory elevatedAssetDirectory;
}

class XrayCoreManager {
  XrayCoreManager({
    OrexAppVersion appVersion = OrexAppVersion.fallback,
  }) : _userAgent = 'OrexRay/${appVersion.version}';

  static const _version = '26.3.27';
  static const version = _version;
  static const _zipName = 'Xray-windows-64-v$_version.zip';
  static const _zipUrl =
      'https://github.com/XTLS/Xray-core/releases/download/v$_version/Xray-windows-64.zip';
  static const _zipSha256 =
      'd004c39288ce9ada487c6f398c7c545f7d749e44bdfdd59dbc9f865afba4e1ad';
  static const _maxDownloadBytes = 64 * 1024 * 1024;
  static const _maxArchiveEntries = 128;
  static const _maxUncompressedBytes = 256 * 1024 * 1024;
  static const _requestTimeout = Duration(seconds: 60);
  static const _requiredRuntimeFiles = {'xray.exe', 'wintun.dll'};
  static const _optionalDataFiles = {'geoip.dat', 'geosite.dat'};

  final String _userAgent;

  Future<XrayCoreInstall> ensureInstalled({
    void Function(double progress)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final assetDirectory = Directory(p.join(support.path, 'xray-core'));
    await assetDirectory.create(recursive: true);

    final bundledRoot = Directory(
      p.join(File(Platform.resolvedExecutable).parent.path, 'xray-core'),
    );
    final bundledArchive = File(p.join(bundledRoot.path, _zipName));
    if (await bundledArchive.exists()) {
      try {
        return await _verifyInstall(
          runtimeDirectory: bundledRoot,
          trustedArchive: bundledArchive,
          assetDirectory: assetDirectory,
        );
      } catch (error) {
        if (!kDebugMode) {
          throw StateError(
            'Встроенный Xray Core повреждён или был изменён. '
            'Переустанови OrexRay из доверенного установщика.\n$error',
          );
        }
      }
    }

    if (!kDebugMode) {
      throw StateError(
        'В release-сборке отсутствует встроенный Xray Core. '
        'Пересобери Windows-релиз через windows/installer/prepare_xray_core.ps1 '
        'и переустанови OrexRay.',
      );
    }

    return _ensureDevelopmentInstall(
      support: support,
      assetDirectory: assetDirectory,
      onProgress: onProgress,
    );
  }

  Future<XrayCoreInstall> _verifyInstall({
    required Directory runtimeDirectory,
    required File trustedArchive,
    required Directory assetDirectory,
  }) async {
    final archive = await _readTrustedArchive(trustedArchive);
    final executable = File(p.join(runtimeDirectory.path, 'xray.exe'));
    final wintun = File(p.join(runtimeDirectory.path, 'wintun.dll'));
    if (!await executable.exists() || !await wintun.exists()) {
      throw StateError('Встроенный Xray Core неполный.');
    }
    if (!await _matchesTrustedArchive(
      archive,
      runtimeDirectory,
      fileNames: {..._requiredRuntimeFiles, ..._optionalDataFiles},
    )) {
      throw StateError('Файлы Xray Core не совпали с доверенным архивом.');
    }

    await _initializeAssets(archive, assetDirectory);
    return XrayCoreInstall(
      directory: runtimeDirectory,
      executable: executable,
      assetDirectory: assetDirectory,
      elevatedAssetDirectory: runtimeDirectory,
    );
  }

  Future<XrayCoreInstall> _ensureDevelopmentInstall({
    required Directory support,
    required Directory assetDirectory,
    void Function(double progress)? onProgress,
  }) async {
    final root = Directory(p.join(support.path, 'xray-core-dev'));
    final executable = File(p.join(root.path, 'xray.exe'));
    final wintun = File(p.join(root.path, 'wintun.dll'));
    final trustedArchive = File(p.join(root.path, _zipName));

    await root.create(recursive: true);
    await _removeLegacyDownloads(root);

    Archive? trustedContents;
    if (await trustedArchive.exists()) {
      try {
        trustedContents = await _readTrustedArchive(trustedArchive);
      } catch (_) {
        await trustedArchive.delete();
      }
      if (trustedContents != null &&
          await executable.exists() &&
          await wintun.exists() &&
          await _matchesTrustedArchive(trustedContents, root)) {
        await _initializeAssets(trustedContents, assetDirectory);
        return XrayCoreInstall(
          directory: root,
          executable: executable,
          assetDirectory: assetDirectory,
          elevatedAssetDirectory: assetDirectory,
        );
      }
    }

    if (!await trustedArchive.exists()) {
      final temporary = File('${trustedArchive.path}.download');
      if (await temporary.exists()) await temporary.delete();
      try {
        await _download(_zipUrl, temporary, onProgress: onProgress);
        await _verifyExpectedHash(temporary);
        await temporary.rename(trustedArchive.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }

    final archive = trustedContents ?? await _readTrustedArchive(trustedArchive);
    await _extractTrustedRuntime(archive, root);
    await _initializeAssets(archive, assetDirectory);

    if (!await executable.exists() || !await wintun.exists()) {
      throw StateError(
        'Xray скачался, но в архиве не найдены xray.exe и wintun.dll.',
      );
    }
    if (!await _matchesTrustedArchive(archive, root)) {
      throw StateError('Установленные файлы Xray не прошли повторную проверку.');
    }

    return XrayCoreInstall(
      directory: root,
      executable: executable,
      assetDirectory: assetDirectory,
      elevatedAssetDirectory: assetDirectory,
    );
  }

  Future<void> _download(
    String url,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient()
      ..userAgent = _userAgent
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub вернул HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final total = response.contentLength;
      if (total > _maxDownloadBytes) {
        throw const FormatException('Архив Xray Core больше 64 МБ.');
      }

      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response.timeout(_requestTimeout)) {
          received += chunk.length;
          if (received > _maxDownloadBytes) {
            throw const FormatException('Архив Xray Core больше 64 МБ.');
          }
          sink.add(chunk);
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      onProgress?.call(1);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verifyExpectedHash(File file) async {
    if (!await file.exists() || await file.length() > _maxDownloadBytes) {
      throw StateError('SHA-256 скачанного Xray Core не совпал.');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != _zipSha256) {
      throw StateError('SHA-256 скачанного Xray Core не совпал.');
    }
  }

  Future<Archive> _readTrustedArchive(File archiveFile) async {
    final length = await archiveFile.length();
    if (length <= 0 || length > _maxDownloadBytes) {
      throw const FormatException('Недопустимый размер архива Xray Core.');
    }
    final bytes = await archiveFile.readAsBytes();
    if (sha256.convert(bytes).toString() != _zipSha256) {
      throw StateError('SHA-256 сохранённого Xray Core не совпал.');
    }
    return _decodeBoundedArchive(bytes);
  }

  Future<void> _extractTrustedRuntime(
    Archive archive,
    Directory destination,
  ) async {
    final entries = _runtimeEntries(archive);
    for (final fileName in _requiredRuntimeFiles) {
      final entry = entries[fileName];
      if (entry == null) {
        throw FormatException('В архиве Xray отсутствует $fileName.');
      }
      await _writeEntryAtomically(
        entry,
        File(p.join(destination.path, fileName)),
      );
    }
  }

  Future<void> _initializeAssets(
    Archive archive,
    Directory assetDirectory,
  ) async {
    await assetDirectory.create(recursive: true);
    final entries = _runtimeEntries(archive);
    for (final fileName in _optionalDataFiles) {
      final output = File(p.join(assetDirectory.path, fileName));
      if (await output.exists()) continue;
      final entry = entries[fileName];
      if (entry != null) await _writeEntryAtomically(entry, output);
    }
  }

  Future<bool> _matchesTrustedArchive(
    Archive archive,
    Directory destination, {
    Set<String> fileNames = _requiredRuntimeFiles,
  }) async {
    try {
      final entries = _runtimeEntries(archive);
      for (final fileName in fileNames) {
        final entry = entries[fileName];
        final installed = File(p.join(destination.path, fileName));
        if (entry == null || !await installed.exists()) return false;
        final expected = sha256.convert(_entryBytes(entry)).toString();
        final actual = (await sha256.bind(installed.openRead()).first).toString();
        if (actual != expected) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Archive _decodeBoundedArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > _maxArchiveEntries) {
      throw const FormatException('В архиве Xray Core слишком много файлов.');
    }
    var totalSize = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      totalSize += entry.size;
      if (entry.size > _maxUncompressedBytes ||
          totalSize > _maxUncompressedBytes) {
        throw const FormatException(
          'Архив Xray Core слишком велик после распаковки.',
        );
      }
    }
    return archive;
  }

  Map<String, ArchiveFile> _runtimeEntries(Archive archive) {
    final allowed = {..._requiredRuntimeFiles, ..._optionalDataFiles};
    final result = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = p.normalize(entry.name).replaceAll('\\', '/');
      if (normalized.startsWith('../') || p.isAbsolute(normalized)) continue;
      final fileName = p.basename(normalized).toLowerCase();
      if (!allowed.contains(fileName)) continue;
      if (result.containsKey(fileName)) {
        throw FormatException('Архив Xray содержит дубликат $fileName.');
      }
      result[fileName] = entry;
    }
    return result;
  }

  List<int> _entryBytes(ArchiveFile entry) {
    final content = entry.content;
    if (content is List<int>) return content;
    throw FormatException('Не удалось прочитать ${entry.name} из архива Xray.');
  }

  Future<void> _writeEntryAtomically(ArchiveFile entry, File destination) async {
    final temporary = File('${destination.path}.new');
    final backup = File('${destination.path}.old');
    if (await temporary.exists()) await temporary.delete();
    if (await backup.exists()) await backup.delete();
    try {
      await temporary.writeAsBytes(_entryBytes(entry), flush: true);
      if (await destination.exists()) await destination.rename(backup.path);
      try {
        await temporary.rename(destination.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await backup.exists() && !await destination.exists()) {
          await backup.rename(destination.path);
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _removeLegacyDownloads(Directory root) async {
    for (final name in const ['xray-download.zip', 'xray-download.zip.dgst']) {
      final file = File(p.join(root.path, name));
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup of files from older OrexRay versions.
        }
      }
    }
  }
}
