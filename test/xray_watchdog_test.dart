import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/platform/windows/xray_watchdog.dart';

void main() {
  test('does not restart configuration or port failures', () {
    final config = XrayExitClassifier.classify(
      exitCode: 23,
      logs: const ['Failed to load config: invalid field'],
    );
    final port = XrayExitClassifier.classify(
      exitCode: 1,
      logs: const ['listen tcp 127.0.0.1:20809: address already in use'],
    );

    expect(config.canRestart, isFalse);
    expect(config.kind, XrayExitKind.configuration);
    expect(port.canRestart, isFalse);
    expect(port.kind, XrayExitKind.portConflict);
    expect(port.message, contains('20809'));
  });

  test('restart budget allows only three restarts per minute', () {
    final budget = XrayRestartBudget();
    final now = DateTime(2026, 7, 7, 12);

    expect(budget.tryTake(now: now), isTrue);
    expect(budget.tryTake(now: now.add(const Duration(seconds: 10))), isTrue);
    expect(budget.tryTake(now: now.add(const Duration(seconds: 20))), isTrue);
    expect(budget.tryTake(now: now.add(const Duration(seconds: 30))), isFalse);
    expect(budget.tryTake(now: now.add(const Duration(seconds: 61))), isTrue);
  });
}
