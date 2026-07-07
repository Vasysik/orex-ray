import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Windows auto-elevation is opt-in and persists', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    expect(settings.windowsRunAsAdministrator, isFalse);

    await settings.setWindowsRunAsAdministrator(true);
    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    expect(reloaded.windowsRunAsAdministrator, isTrue);
  });
}
