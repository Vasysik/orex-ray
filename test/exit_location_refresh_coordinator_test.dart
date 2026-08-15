import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/egress/exit_location_refresh_coordinator.dart';

void main() {
  test('Android event-driven policy never schedules a periodic refresh', () {
    final coordinator = ExitLocationRefreshCoordinator(
      policy: const ExitLocationRefreshPolicy.eventDriven(),
      activeTargetId: () => 'profile-a',
      canRefresh: (_, __) => true,
      refresh: (_, __) async {},
    );
    addTearDown(coordinator.dispose);

    coordinator.startPeriodic();

    expect(coordinator.hasPeriodicRefresh, isFalse);
  });

  test('deduplicates concurrent refreshes for one profile', () async {
    final release = Completer<void>();
    var calls = 0;
    final coordinator = ExitLocationRefreshCoordinator(
      policy: const ExitLocationRefreshPolicy.eventDriven(),
      activeTargetId: () => 'profile-a',
      canRefresh: (_, __) => true,
      refresh: (_, __) {
        calls++;
        return release.future;
      },
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.request(
      'profile-a',
      trigger: ExitLocationRefreshTrigger.connected,
    );
    final second = coordinator.request(
      'profile-a',
      trigger: ExitLocationRefreshTrigger.manualPing,
    );

    expect(calls, 1);
    release.complete();
    await Future.wait([first, second]);
  });

  test('connection, recovery and manual requests use one coordinator path',
      () async {
    final triggers = <ExitLocationRefreshTrigger>[];
    final coordinator = ExitLocationRefreshCoordinator(
      policy: const ExitLocationRefreshPolicy.eventDriven(),
      activeTargetId: () => 'profile-a',
      canRefresh: (_, __) => true,
      refresh: (_, trigger) async => triggers.add(trigger),
    );
    addTearDown(coordinator.dispose);

    for (final trigger in [
      ExitLocationRefreshTrigger.connected,
      ExitLocationRefreshTrigger.reconnected,
      ExitLocationRefreshTrigger.manualPing,
      ExitLocationRefreshTrigger.networkRecovered,
    ]) {
      await coordinator.request('profile-a', trigger: trigger);
    }

    expect(
      triggers,
      [
        ExitLocationRefreshTrigger.connected,
        ExitLocationRefreshTrigger.reconnected,
        ExitLocationRefreshTrigger.manualPing,
        ExitLocationRefreshTrigger.networkRecovered,
      ],
    );
  });

  test('Windows periodic refresh goes through the same coordinator', () {
    fakeAsync((async) {
      final triggers = <ExitLocationRefreshTrigger>[];
      final coordinator = ExitLocationRefreshCoordinator(
        policy: const ExitLocationRefreshPolicy.windows(
          periodicInterval: Duration(minutes: 5),
        ),
        activeTargetId: () => 'profile-a',
        canRefresh: (_, __) => true,
        refresh: (_, trigger) async => triggers.add(trigger),
      );
      addTearDown(coordinator.dispose);

      coordinator.startPeriodic();
      async.elapse(const Duration(minutes: 5));

      expect(coordinator.hasPeriodicRefresh, isTrue);
      expect(triggers, [ExitLocationRefreshTrigger.periodic]);
    });
  });
}
