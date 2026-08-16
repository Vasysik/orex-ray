import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('latency probe service defaults to Cloudflare and persists custom URL',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(settings.dispose);

    expect(settings.latencyProbePreset, LatencyProbePreset.cloudflare);
    expect(
      settings.latencyProbeUri.toString(),
      'https://cloudflare.com/cdn-cgi/trace',
    );

    await settings.setLatencyProbePreset(LatencyProbePreset.google);
    expect(settings.latencyProbeUri.toString(),
        'https://www.gstatic.com/generate_204');

    await settings
        .setCustomLatencyProbeUrl(' https://probe.example.com/ready ');
    expect(settings.latencyProbePreset, LatencyProbePreset.custom);
    expect(settings.customLatencyProbeUrl, 'https://probe.example.com/ready');

    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.latencyProbePreset, LatencyProbePreset.custom);
    expect(
      reloaded.latencyProbeUri.toString(),
      'https://probe.example.com/ready',
    );
  });

  test('latency probe service rejects non-public or invalid endpoints',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(settings.dispose);

    for (final value in [
      'ftp://example.com/check',
      'https://user:password@example.com/check',
      'http://localhost/check',
      'http://localhost./check',
      'http://127.0.0.1/check',
      'http://[::1]/check',
      'https://example.com/check#fragment',
    ]) {
      await expectLater(
        settings.setCustomLatencyProbeUrl(value),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('invalid stored custom latency probe falls back to Cloudflare',
      () async {
    SharedPreferences.setMockInitialValues({
      'orex_ray_latency_probe_preset_v1': 'custom',
      'orex_ray_custom_latency_probe_url_v1': 'http://127.0.0.1/health',
    });
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(settings.dispose);

    expect(settings.latencyProbePreset, LatencyProbePreset.cloudflare);
    expect(
      settings.latencyProbeUri.toString(),
      'https://cloudflare.com/cdn-cgi/trace',
    );
  });

  test('Windows auto-elevation is opt-in and persists', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    expect(settings.windowsRunAsAdministrator, isFalse);
    expect(settings.autoStart, isFalse);
    expect(settings.autoConnectOnStartup, isFalse);

    await settings.setWindowsRunAsAdministrator(true);
    await settings.setAutoStart(true);
    await settings.setAutoConnectOnStartup(true);
    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    expect(reloaded.windowsRunAsAdministrator, isTrue);
    expect(reloaded.autoStart, isTrue);
    expect(reloaded.autoConnectOnStartup, isTrue);
  });
}
