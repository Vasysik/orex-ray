import 'dart:async';
import 'dart:math';

import 'tunnel_engine.dart';
import 'tunnel_models.dart';

/// Используется только в тестах и превью. Production-приложение его не создаёт.
class MockTunnelEngine implements TunnelEngine {
  MockTunnelEngine()
      : _current = const TunnelSnapshot(
          status: TunnelStatus.disconnected,
          stats: TrafficStats(),
        );

  final _controller = StreamController<TunnelSnapshot>.broadcast();
  final _random = Random();
  Timer? _timer;
  DateTime? _connectedAt;
  TunnelSnapshot _current;

  @override
  Stream<TunnelSnapshot> get snapshots => _controller.stream;

  @override
  TunnelSnapshot get current => _current;

  @override
  Set<ConnectionMode> get supportedModes => const {
        ConnectionMode.vpnTun,
        ConnectionMode.systemProxy,
        ConnectionMode.localProxy,
      };

  void _emit(TunnelSnapshot value) {
    _current = value;
    _controller.add(value);
  }

  @override
  Future<void> start(TunnelTarget profile, ConnectionMode mode) async {
    if (_current.status == TunnelStatus.connected ||
        _current.status == TunnelStatus.connecting) {
      return;
    }

    _emit(TunnelSnapshot(
      status: TunnelStatus.connecting,
      mode: mode,
      profile: profile,
      stats: const TrafficStats(),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    _connectedAt = DateTime.now();
    _emit(TunnelSnapshot(
      status: TunnelStatus.connected,
      mode: mode,
      profile: profile,
      stats: const TrafficStats(),
    ));

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final previous = _current.stats;
      _emit(TunnelSnapshot(
        status: TunnelStatus.connected,
        mode: mode,
        profile: profile,
        stats: TrafficStats(
          downloadBytes: previous.downloadBytes + _random.nextInt(20000),
          uploadBytes: previous.uploadBytes + _random.nextInt(5000),
          duration: DateTime.now().difference(_connectedAt!),
        ),
      ));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _connectedAt = null;
    _emit(TunnelSnapshot(
      status: TunnelStatus.disconnected,
      mode: _current.mode,
      profile: _current.profile,
      stats: const TrafficStats(),
    ));
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
