import 'dart:io';

import '../core/settings/connection_settings_controller.dart';
import '../core/tunnel/tunnel_engine.dart';
import 'android/android_xray_engine.dart';
import 'common/unsupported_tunnel_engine.dart';
import 'windows/windows_xray_engine.dart';

TunnelEngine createTunnelEngine({
  required ConnectionSettingsController settings,
}) {
  if (Platform.isWindows) {
    return WindowsXrayEngine(settings: settings);
  }
  if (Platform.isAndroid) {
    return AndroidXrayEngine(settings: settings);
  }
  return UnsupportedTunnelEngine(Platform.operatingSystem);
}
