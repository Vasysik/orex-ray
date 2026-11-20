import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/tunnel_models.dart';
import 'package:orex_ray/platform/windows/windows_xray_engine.dart';
import 'package:orex_ray/platform/windows/xray_core_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopping during Windows core preparation discards its failure',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    final core = _PendingCoreManager();
    final engine = WindowsXrayEngine(settings: settings, coreManager: core);
    addTearDown(() async {
      await engine.dispose();
      settings.dispose();
    });
    final target = TunnelTarget.single(
      TunnelProfile(
        id: 'cancel-start',
        name: 'Test proxy',
        address: '127.0.0.1',
        port: 443,
        userId: '11111111-1111-4111-8111-111111111111',
      ),
    );

    final start = engine.start(target, ConnectionMode.localProxy);
    await core.started.future;
    final stop = engine.stop();
    expect(engine.current.status, TunnelStatus.disconnecting);
    await Future.wait([start, stop]);
    expect(engine.current.status, TunnelStatus.disconnected);

    core.install.completeError(StateError('Obsolete preparation failure'));
    await Future<void>.delayed(Duration.zero);
    expect(engine.current.status, TunnelStatus.disconnected);
    expect(engine.current.errorMessage, isNull);
  });
}

class _PendingCoreManager extends XrayCoreManager {
  final started = Completer<void>();
  final install = Completer<XrayCoreInstall>();

  @override
  Future<XrayCoreInstall> ensureInstalled({
    void Function(double progress)? onProgress,
  }) {
    started.complete();
    return install.future;
  }
}
