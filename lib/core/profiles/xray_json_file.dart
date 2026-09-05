import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class XrayJsonFileExporter {
  const XrayJsonFileExporter();

  static const _androidChannel = MethodChannel('ru.orex.ray/file_export');

  /// Returns true after a file was saved and false when the picker was closed.
  Future<bool> save({
    required String content,
    required String suggestedName,
  }) async {
    final fileName = suggestedName.toLowerCase().endsWith('.json')
        ? suggestedName
        : '$suggestedName.json';
    if (Platform.isAndroid) {
      final uri = await _androidChannel.invokeMethod<String>('saveJson', {
        'fileName': fileName,
        'content': content,
      });
      return uri != null && uri.isNotEmpty;
    }

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Xray JSON',
          extensions: ['json'],
        ),
      ],
    );
    if (location == null) return false;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
      name: fileName,
    );
    await file.saveTo(location.path);
    return true;
  }
}
