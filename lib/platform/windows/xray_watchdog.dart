import 'dart:collection';

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
      return const XrayExitDecision(
        kind: XrayExitKind.configuration,
        canRestart: false,
        message: 'Xray отклонил конфигурацию. Автоперезапуск остановлен.',
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
            ? 'Xray не смог занять локальный порт. Проверь настройки портов.'
            : 'Локальный порт $port уже занят. Измени порт или закрой другой процесс.',
      );
    }
    if (_containsAny(text, const [
      'access is denied',
      'access denied',
      'permission denied',
      'operation requires elevation',
    ])) {
      return const XrayExitDecision(
        kind: XrayExitKind.permission,
        canRestart: false,
        message: 'Xray остановлен из-за недостаточных прав доступа.',
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
      return const XrayExitDecision(
        kind: XrayExitKind.transient,
        canRestart: true,
        message: 'Сеть временно недоступна. OrexRay восстановит подключение.',
      );
    }
    return XrayExitDecision(
      kind: XrayExitKind.crash,
      canRestart: exitCode != 0,
      message: exitCode == 0
          ? 'Xray завершился без ошибки.'
          : 'Xray неожиданно завершился с кодом $exitCode.',
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
