import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/app_version.dart';

void main() {
  group('OrexAppVersion.displayBuildNumberFromPlatform', () {
    test('extracts the logical build from Flutter split-per-ABI codes', () {
      expect(OrexAppVersion.displayBuildNumberFromPlatform('1003'), '3');
      expect(OrexAppVersion.displayBuildNumberFromPlatform('2003'), '3');
      expect(OrexAppVersion.displayBuildNumberFromPlatform('4001'), '1');
    });

    test('keeps ordinary and unknown build numbers unchanged', () {
      expect(OrexAppVersion.displayBuildNumberFromPlatform('3'), '3');
      expect(OrexAppVersion.displayBuildNumberFromPlatform('1000'), '1000');
      expect(OrexAppVersion.displayBuildNumberFromPlatform('5003'), '5003');
      expect(OrexAppVersion.displayBuildNumberFromPlatform('dev'), 'dev');
    });

    test('trims platform values before displaying them', () {
      expect(OrexAppVersion.displayBuildNumberFromPlatform(' 2003 '), '3');
    });
  });
}
