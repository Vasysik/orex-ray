import 'package:flutter/services.dart';

class WindowsElevationController {
  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');

  static Future<bool> isElevated() async =>
      await _channel.invokeMethod<bool>('isProcessElevated') ?? false;

  static Future<bool> isProtectedInstall() async =>
      await _channel.invokeMethod<bool>('isProtectedInstall') ?? false;

  static Future<bool> restartElevated() async =>
      await _channel.invokeMethod<bool>('restartElevated') ?? false;

  static Future<bool> maybeRestartOnStartup({required bool enabled}) async {
    if (!enabled) return false;
    if (!await isProtectedInstall()) return false;
    if (await isElevated()) return false;
    return restartElevated();
  }
}
