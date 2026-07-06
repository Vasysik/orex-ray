import 'dart:async';
import 'dart:io';

import '../tunnel/tunnel_models.dart';

class LatencyProbe {
  const LatencyProbe({this.timeout = const Duration(seconds: 4)});

  final Duration timeout;

  Future<int?> measure(TunnelProfile profile) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        profile.address,
        profile.port,
        timeout: timeout,
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds.clamp(1, 60000).toInt();
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }
}
