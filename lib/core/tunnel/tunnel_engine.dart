import 'tunnel_models.dart';

abstract interface class TunnelEngine {
  Stream<TunnelSnapshot> get snapshots;

  TunnelSnapshot get current;

  Set<ConnectionMode> get supportedModes;

  Future<void> start(TunnelTarget profile, ConnectionMode mode);

  Future<void> stop();

  Future<void> dispose();
}
