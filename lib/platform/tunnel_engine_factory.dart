import 'dart:io';

import '../core/tunnel/tunnel_engine.dart';
import 'android/android_xray_engine.dart';
import 'common/unsupported_tunnel_engine.dart';
import 'windows/windows_xray_engine.dart';

TunnelEngine createTunnelEngine() {
  if (Platform.isWindows) {
    return WindowsXrayEngine();
  }
  if (Platform.isAndroid) {
    return AndroidXrayEngine();
  }
  return UnsupportedTunnelEngine(Platform.operatingSystem);
}
