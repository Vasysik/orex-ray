import 'package:flutter/services.dart';

class WindowsNetworkController {
  const WindowsNetworkController._();

  static const _channel = MethodChannel('ru.orex.ray/windows_lifecycle');

  static Future<String?> bestOutboundInterface() async {
    final value = await _channel.invokeMethod<String>('getBestOutboundInterface');
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
