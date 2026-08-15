import 'dart:async';

/// Why an exit-location lookup was requested. Keeping the reason explicit
/// prevents a platform-specific timer from quietly becoming a second refresh
/// implementation.
enum ExitLocationRefreshTrigger {
  connected,
  reconnected,
  profileChanged,
  manualPing,
  diagnostics,
  networkRecovered,
  periodic,
}

/// Platform policy for exit-location refreshes.
///
/// Android is deliberately event-driven: a foreground VPN must not wake up
/// just to re-check a country that is not currently visible. Windows keeps its
/// existing periodic refresh through this same coordinator.
class ExitLocationRefreshPolicy {
  const ExitLocationRefreshPolicy.eventDriven() : periodicInterval = null;

  const ExitLocationRefreshPolicy.windows({
    this.periodicInterval = const Duration(minutes: 5),
  });

  factory ExitLocationRefreshPolicy.forOperatingSystem(String operatingSystem) {
    return operatingSystem == 'windows'
        ? const ExitLocationRefreshPolicy.windows()
        : const ExitLocationRefreshPolicy.eventDriven();
  }

  final Duration? periodicInterval;

  bool allows(ExitLocationRefreshTrigger trigger) =>
      trigger != ExitLocationRefreshTrigger.periodic ||
      periodicInterval != null;
}

/// Serializes refreshes for each target and owns the optional periodic policy.
///
/// The actual probe stays with the tunnel controller, where the local Xray
/// proxy and the persisted exit-location cache are available. This class makes
/// all entry points (connect, manual refresh, recovery, and Windows timer)
/// share the same eligibility and de-duplication path.
class ExitLocationRefreshCoordinator {
  ExitLocationRefreshCoordinator({
    required ExitLocationRefreshPolicy policy,
    required String? Function() activeTargetId,
    required bool Function(String targetId, ExitLocationRefreshTrigger trigger)
        canRefresh,
    required Future<void> Function(
      String targetId,
      ExitLocationRefreshTrigger trigger,
    ) refresh,
  })  : _policy = policy,
        _activeTargetId = activeTargetId,
        _canRefresh = canRefresh,
        _refresh = refresh;

  final ExitLocationRefreshPolicy _policy;
  final String? Function() _activeTargetId;
  final bool Function(String targetId, ExitLocationRefreshTrigger trigger)
      _canRefresh;
  final Future<void> Function(
    String targetId,
    ExitLocationRefreshTrigger trigger,
  ) _refresh;

  final Map<String, Future<void>> _inFlight = {};
  Timer? _periodicTimer;

  bool get hasPeriodicRefresh => _periodicTimer != null;

  Future<void> request(
    String targetId, {
    required ExitLocationRefreshTrigger trigger,
  }) {
    if (!_policy.allows(trigger) || !_canRefresh(targetId, trigger)) {
      return Future<void>.value();
    }

    final existing = _inFlight[targetId];
    if (existing != null) return existing;

    final refresh = Future<void>.sync(() => _refresh(targetId, trigger));
    _inFlight[targetId] = refresh;
    unawaited(
      refresh.then(
        (_) => _removeInFlight(targetId, refresh),
        onError: (_, __) => _removeInFlight(targetId, refresh),
      ),
    );
    return refresh;
  }

  void startPeriodic() {
    final interval = _policy.periodicInterval;
    if (interval == null || _periodicTimer != null) return;
    _periodicTimer = Timer.periodic(interval, (_) {
      final targetId = _activeTargetId();
      if (targetId == null) return;
      unawaited(
        request(
          targetId,
          trigger: ExitLocationRefreshTrigger.periodic,
        ),
      );
    });
  }

  void stopPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void dispose() => stopPeriodic();

  void _removeInFlight(String targetId, Future<void> refresh) {
    if (identical(_inFlight[targetId], refresh)) {
      _inFlight.remove(targetId);
    }
  }
}
