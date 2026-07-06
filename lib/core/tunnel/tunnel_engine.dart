import 'tunnel_models.dart';

abstract interface class TunnelEngine {
  Stream<TunnelSnapshot> get snapshots;

  TunnelSnapshot get current;

  Set<ConnectionMode> get supportedModes;

  Future<void> start(TunnelTarget profile, ConnectionMode mode);

  Future<void> stop();

  Future<void> dispose();
}

/// Optional bridge for engines that can update native/background UI while a
/// tunnel is already running (for example Android's foreground notification).
abstract interface class TunnelRuntimeMetadataSink {
  Future<void> updateTargetMetadata(TunnelTarget target);
}
