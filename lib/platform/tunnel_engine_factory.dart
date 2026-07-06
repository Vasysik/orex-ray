import 'dart:io';

import '../core/apps/app_routing_controller.dart';
import '../core/settings/connection_settings_controller.dart';
import '../core/tunnel/tunnel_engine.dart';
import 'android/android_xray_engine.dart';
import 'common/unsupported_tunnel_engine.dart';
import 'windows/windows_xray_engine.dart';

TunnelEngine createTunnelEngine({
  required ConnectionSettingsController settings,
  required AppRoutingController appRouting,
}) {
  if (Platform.isWindows) {
    return WindowsXrayEngine(settings: settings);
  }
  if (Platform.isAndroid) {
    return AndroidXrayEngine(settings: settings, appRouting: appRouting);
  }
  return UnsupportedTunnelEngine(Platform.operatingSystem);
}
