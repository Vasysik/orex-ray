import 'dart:async';

import '../../core/tunnel/tunnel_engine.dart';
import '../../core/tunnel/tunnel_models.dart';

class UnsupportedTunnelEngine implements TunnelEngine {
  UnsupportedTunnelEngine(this.platformName)
      : _current = const TunnelSnapshot(
          status: TunnelStatus.disconnected,
          stats: TrafficStats(),
        );

  final String platformName;
  final _controller = StreamController<TunnelSnapshot>.broadcast();
  TunnelSnapshot _current;

  @override
  TunnelSnapshot get current => _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _controller.stream;

  @override
  Set<ConnectionMode> get supportedModes => const {ConnectionMode.localProxy};

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    _current = TunnelSnapshot(
      status: TunnelStatus.error,
      mode: mode,
      profile: profile,
      stats: const TrafficStats(),
      errorMessage:
          'VPN-движок для $platformName не поддерживается. OrexRay сейчас работает на Windows и Android.',
    );
    _controller.add(_current);
  }

  @override
  Future<void> stop() async {
    _current = _current.copyWith(
      status: TunnelStatus.disconnected,
      stats: const TrafficStats(),
      clearError: true,
      clearMessage: true,
    );
    _controller.add(_current);
  }

  @override
  Future<void> dispose() => _controller.close();
}
