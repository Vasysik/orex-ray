import 'dart:io';

import 'package:flutter/services.dart';

class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static const _androidChannel = MethodChannel('ru.orex.ray/tunnel');

  static Future<void> open(String value) async {
    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Некорректная внешняя ссылка');
    }

    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>(
        'openExternalUrl',
        <String, Object?>{'url': uri.toString()},
      );
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        <String>[uri.toString()],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    throw const FormatException('Открытие ссылок на этой платформе не поддерживается');
  }
}
