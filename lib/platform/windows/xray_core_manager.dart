import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class XrayCoreInstall {
  const XrayCoreInstall({
    required this.directory,
    required this.executable,
  });

  final Directory directory;
  final File executable;
}

class XrayCoreManager {
  static const _zipUrl =
      'https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip';
  static const _digestUrl =
      'https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip.dgst';

  Future<XrayCoreInstall> ensureInstalled({
    void Function(double progress)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'xray-core'));
    final executable = File(p.join(root.path, 'xray.exe'));
    final wintun = File(p.join(root.path, 'wintun.dll'));

    if (await executable.exists() && await wintun.exists()) {
      return XrayCoreInstall(directory: root, executable: executable);
    }

    await root.create(recursive: true);
    final zipFile = File(p.join(root.path, 'xray-download.zip'));
    final digestFile = File(p.join(root.path, 'xray-download.zip.dgst'));

    try {
      await _download(_zipUrl, zipFile, onProgress: onProgress);
      await _download(_digestUrl, digestFile);
      await _verify(zipFile, digestFile);
      await _extract(zipFile, root);
    } finally {
      if (await zipFile.exists()) await zipFile.delete();
      if (await digestFile.exists()) await digestFile.delete();
    }

    if (!await executable.exists() || !await wintun.exists()) {
      throw StateError(
        'Xray скачался, но в архиве не найдены xray.exe и wintun.dll.',
      );
    }

    return XrayCoreInstall(directory: root, executable: executable);
  }

  Future<void> _download(
    String url,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    client.userAgent = 'OrexRay/0.6.1';
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub вернул HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call(received / total);
          }
        }
      } finally {
        await sink.close();
      }
      onProgress?.call(1);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verify(File zipFile, File digestFile) async {
    final digestText = await digestFile.readAsString();
    final matches = RegExp(r'\b[a-fA-F0-9]{64}\b').allMatches(digestText);
    if (matches.isEmpty) {
      throw const FormatException('Не удалось прочитать SHA-256 Xray Core.');
    }

    final expected = matches.first.group(0)!.toLowerCase();
    final actual = sha256.convert(await zipFile.readAsBytes()).toString();
    if (actual != expected) {
      throw StateError('SHA-256 скачанного Xray Core не совпал.');
    }
  }

  Future<void> _extract(File zipFile, Directory destination) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    for (final entry in archive) {
      final safeName = p.normalize(entry.name).replaceAll('\\', '/');
      if (safeName.startsWith('../') || p.isAbsolute(safeName)) continue;
      final outputPath = p.join(destination.path, safeName);
      if (entry.isFile) {
        final output = File(outputPath);
        await output.parent.create(recursive: true);
        final content = entry.content;
        if (content is Uint8List) {
          await output.writeAsBytes(content, flush: true);
        } else if (content is List<int>) {
          await output.writeAsBytes(content, flush: true);
        }
      } else {
        await Directory(outputPath).create(recursive: true);
      }
    }
  }
}
