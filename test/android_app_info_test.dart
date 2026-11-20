import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/apps/app_routing_controller.dart';

void main() {
  test('preinstalled launchable apps stay in the main app list', () {
    const youtube = AndroidAppInfo(
      packageName: 'com.google.android.youtube',
      label: 'YouTube',
      isSystem: true,
      hasLauncher: true,
    );
    expect(youtube.isSystemComponent, isFalse);
  });

  test('only system packages without a launcher are hidden by default', () {
    const system = AndroidAppInfo(
      packageName: 'com.android.providers.settings',
      label: 'Settings Storage',
      isSystem: true,
      hasLauncher: false,
    );
    const user = AndroidAppInfo(
      packageName: 'example.service',
      label: 'User service',
      isSystem: false,
      hasLauncher: false,
    );
    expect(system.isSystemComponent, isTrue);
    expect(user.isSystemComponent, isFalse);
  });
}
