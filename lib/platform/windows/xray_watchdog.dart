import 'dart:collection';
import '../../shared/l10n/orex_l10n.dart';

enum XrayExitKind {
  configuration,
  portConflict,
  permission,
  transient,
  crash,
}

class XrayExitDecision {
  const XrayExitDecision({
    required this.kind,
    required this.canRestart,
    required this.message,
  });

  final XrayExitKind kind;
  final bool canRestart;
  final String message;
}

class XrayExitClassifier {
  const XrayExitClassifier._();

  static XrayExitDecision classify({
    required int exitCode,
    required Iterable<String> logs,
  }) {
    final text = logs.join('\n').toLowerCase();
    if (_containsAny(text, const [
      'failed to load config',
      'failed to build config',
      'invalid config',
      'invalid field',
      'failed to parse',
      'syntax error',
    ])) {
      return XrayExitDecision(
        kind: XrayExitKind.configuration,
        canRestart: false,
        message: 'Xray rejected the configuration. Auto-restart stopped.'.tr,
      );
    }
    if (_containsAny(text, const [
      'address already in use',
      'bind: only one usage',
      'failed to listen',
      'port is already occupied',
    ])) {
      final port = RegExp(r'(?:127\.0\.0\.1|0\.0\.0\.0|\[::1\]):(\d{1,5})')
          .firstMatch(text)
          ?.group(1);
      return XrayExitDecision(
        kind: XrayExitKind.portConflict,
        canRestart: false,
        message: port == null
            ? 'Xray could not bind the local port. Check the port settings.'.tr
            : 'Local port {} is already in use. Change the port or close the other process.'.trf([port]),
      );
    }
    if (_containsAny(text, const [
      'access is denied',
      'access denied',
      'permission denied',
      'operation requires elevation',
    ])) {
      return XrayExitDecision(
        kind: XrayExitKind.permission,
        canRestart: false,
        message: 'Xray was stopped due to insufficient permissions.'.tr,
      );
    }
    if (_containsAny(text, const [
      'network is unreachable',
      'no route to host',
      'connection reset',
      'connection refused',
      'temporary failure',
      'timeout',
    ])) {
      return XrayExitDecision(
        kind: XrayExitKind.transient,
        canRestart: true,
        message: 'The network is temporarily unavailable. OrexRay will restore the connection.'.tr,
      );
    }
    return XrayExitDecision(
      kind: XrayExitKind.crash,
      canRestart: exitCode != 0,
      message: exitCode == 0
          ? 'Xray exited without an error.'.tr
          : 'Xray exited unexpectedly with code {}.'.trf([exitCode]),
    );
  }

  static bool _containsAny(String text, Iterable<String> patterns) =>
      patterns.any(text.contains);
}

class XrayRestartBudget {
  XrayRestartBudget({
    this.maxRestarts = 3,
    this.window = const Duration(minutes: 1),
  });

  final int maxRestarts;
  final Duration window;
  final Queue<DateTime> _restarts = Queue<DateTime>();

  int get recentRestartCount => _restarts.length;

  bool tryTake({DateTime? now}) {
    final current = now ?? DateTime.now();
    while (_restarts.isNotEmpty &&
        current.difference(_restarts.first) > window) {
      _restarts.removeFirst();
    }
    if (_restarts.length >= maxRestarts) return false;
    _restarts.addLast(current);
    return true;
  }

  void reset() => _restarts.clear();
}
