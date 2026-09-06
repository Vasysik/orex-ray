import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stats intervals are independent and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(settings.dispose);

    expect(settings.statsIntervalSeconds, 2);
    expect(settings.notificationStatsIntervalSeconds, 5);

    await settings.setStatsIntervalSeconds(15);
    await settings.setNotificationStatsIntervalSeconds(30);

    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.statsIntervalSeconds, 15);
    expect(reloaded.notificationStatsIntervalSeconds, 30);

    await expectLater(
      settings.setStatsIntervalSeconds(4),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      settings.setNotificationStatsIntervalSeconds(2),
      throwsA(isA<FormatException>()),
    );
  });


  test('subscription auto-update interval persists and validates', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(settings.dispose);

    expect(settings.subscriptionAutoUpdateHours, 12);
    expect(settings.subscriptionMetadataRefreshMinutes, 10);
    await settings.setSubscriptionAutoUpdateHours(24);
    await settings.setSubscriptionMetadataRefreshMinutes(30);
    expect(settings.subscriptionAutoUpdateHours, 24);
    expect(settings.subscriptionMetadataRefreshMinutes, 30);

    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'windows',
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.subscriptionAutoUpdateHours, 24);
    expect(reloaded.subscriptionMetadataRefreshMinutes, 30);

    await expectLater(
      settings.setSubscriptionAutoUpdateHours(2),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      settings.setSubscriptionMetadataRefreshMinutes(20),
      throwsA(isA<FormatException>()),
    );
  });

  test('ping interval defaults, validates and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(settings.dispose);

    expect(settings.pingIntervalSeconds, 60);
    await settings.setPingIntervalSeconds(120);
    expect(settings.pingIntervalSeconds, 120);
    await expectLater(
      settings.setPingIntervalSeconds(17),
      throwsA(isA<FormatException>()),
    );

    final reloaded = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.pingIntervalSeconds, 120);
  });

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
