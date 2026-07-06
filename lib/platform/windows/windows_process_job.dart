import 'package:flutter/services.dart';

class WindowsProcessJob {
  const WindowsProcessJob._();

  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');

  static Future<void> attach(int processId) async {
    await _channel.invokeMethod<void>('attachProcess', {'pid': processId});
  }

  static Future<int> terminateStaleProcesses(String executablePath) async {
    final result = await _channel.invokeMethod<int>(
      'terminateProcessesByPath',
      {'path': executablePath},
    );
    return result ?? 0;
  }
}
