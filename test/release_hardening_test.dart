import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android release hardening', () {
    test('manifest disables backup and cleartext traffic', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        manifest,
        contains('android:networkSecurityConfig="@xml/network_security_config"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('VPN service is not exported', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final serviceStart = manifest.indexOf(
        'android:name=".OrexRayVpnService"',
      );

      expect(serviceStart, greaterThanOrEqualTo(0));
      final serviceEnd = manifest.indexOf('</service>', serviceStart);
      expect(serviceEnd, greaterThan(serviceStart));
      final serviceBlock = manifest.substring(serviceStart, serviceEnd);
      expect(serviceBlock, contains('android:exported="false"'));
      expect(
        serviceBlock,
        contains('android:permission="android.permission.BIND_VPN_SERVICE"'),
      );
    });

    test('release signing cannot silently fall back to debug signing', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(gradle, contains('Android release signing is not configured'));
      expect(gradle, contains('OREX_ALLOW_UNSIGNED_ANDROID_RELEASE'));
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });

    test('notification shows latency without the Ping label', () {
      final service = File(
        'android/app/src/main/kotlin/ru/orex/ray/OrexRayVpnService.kt',
      ).readAsStringSync();

      expect(service, contains('activeLatencyMs?.let { parts += "\$it мс" }'));
      expect(service, isNot(contains('parts += "Ping \$it мс"')));
    });

    test('release secrets are ignored by git', () {
      final gitignore = File('.gitignore').readAsStringSync();

      expect(gitignore, contains('android/key.properties'));
      expect(gitignore, contains('android/secrets/'));
      expect(gitignore, contains('**/*.jks'));
    });

    test('repository root is free from milestone and hotfix notes', () {
      final forbiddenPrefixes = <String>[
        'MILESTONE_',
        'HOTFIX_',
        'UPDATE_',
      ];
      final rootFiles = Directory.current
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList(growable: false);

      expect(
        rootFiles.where(
          (name) => forbiddenPrefixes.any(
            (prefix) => name.startsWith(prefix),
          ),
        ),
        isEmpty,
      );
      expect(rootFiles, isNot(contains('RELEASE_CHECKLIST.md')));
      expect(rootFiles, isNot(contains('SECURITY_REVIEW.md')));
      expect(rootFiles, isNot(contains('NATIVE_WINDOWS_VPN.md')));
    });

    test('release docs target private distribution and current version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final readme = File('README.md').readAsStringSync();
      final builds = File('docs/release-builds.md').readAsStringSync();

      expect(pubspec, contains('version: 0.6.2+1'));
      expect(readme, contains('0.6.2+1'));
      expect(builds, contains('0.6.2+1'));
      expect(builds.toLowerCase(), isNot(contains('google play')));
      expect(builds.toLowerCase(), isNot(contains('play market')));
    });

    test('repository keeps release instructions in docs without ps1 helpers', () {
      expect(File('docs/release-builds.md').existsSync(), isTrue);
      final tool = Directory('tool');
      if (tool.existsSync()) {
        expect(
          tool.listSync(recursive: true).whereType<File>().any(
                (file) => file.path.toLowerCase().endsWith('.ps1'),
              ),
          isFalse,
        );
      }
    });
  });
}
