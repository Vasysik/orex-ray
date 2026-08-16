import '../diagnostics/tunnel_diagnostics.dart';
import 'tunnel_models.dart';

abstract interface class TunnelEngine {
  Stream<TunnelSnapshot> get snapshots;

  TunnelSnapshot get current;

  Set<ConnectionMode> get supportedModes;

  Future<void> start(TunnelTarget profile, ConnectionMode mode);

  Future<void> stop();

  Future<void> dispose();
}

/// Optional startup barrier for engines whose native runtime can outlive the
/// Flutter activity.
///
/// Android's foreground VPN service may still be connected when a new Dart
/// engine is created. Consumers must wait for this barrier before deciding
/// that a direct probe or a new connection is safe.
abstract interface class TunnelInitialStateSync {
  Future<void> waitForInitialState();
}

/// Optional bridge for engines that can update native/background UI while a
/// tunnel is already running (for example Android's foreground notification).
abstract interface class TunnelRuntimeMetadataSink {
  Future<void> updateTargetMetadata(TunnelTarget target);
}

/// Optional bridge for a running engine whose statistics are only needed while
/// the application UI has an active consumer.
abstract interface class TunnelStatsConsumerSink {
  Future<void> setStatsUiActive(bool active);
}

/// Optional bridge for settings that affect a running native foreground
/// service. These values must be applied without requiring a reconnect.
abstract interface class TunnelRuntimeSettingsSink {
  Future<void> updateRuntimeSettings({
    required int statsIntervalSeconds,
    required bool showNotificationSpeed,
    required bool showNotificationPing,
    required bool allowNotificationDismissal,
  });
}

enum TunnelRecoveryReason {
  networkChanged,
  systemResume,
}

/// Optional recovery hook for engines that can rebuild a live connection
/// after sleep or a physical network transition.
abstract interface class TunnelRecoverySink {
  Future<void> recover(TunnelRecoveryReason reason);
}

/// Optional diagnostics provider. Reports must already be sanitized by the
/// engine and must not contain UUIDs, access tokens, private keys or configs.
abstract interface class TunnelDiagnosticsProvider {
  Future<TunnelDiagnostics> collectDiagnostics();
}

/// Optional sink for app-level diagnostic events that should appear in the
/// diagnostics report alongside engine logs. Implementations must never log
/// profile credentials or raw connection links.
abstract interface class TunnelDiagnosticEventSink {
  void addDiagnosticEvent(String message);
}

/// Optional maintenance hook for engines with a replaceable Xray runtime.
/// Implementations must verify the pinned artifact before writing any file.
abstract interface class TunnelCoreMaintenance {
  Future<void> reinstallCore({void Function(double progress)? onProgress});
}
