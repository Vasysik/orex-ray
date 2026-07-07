import 'package:flutter/services.dart';

class AndroidStartupController {
  const AndroidStartupController._();

  static const _channel = MethodChannel('ru.orex.ray/tunnel');

  static Future<void> setAutoConnectOnBoot(bool enabled) async {
    await _channel.invokeMethod<void>('setAutoConnectOnBoot', enabled);
  }
}
