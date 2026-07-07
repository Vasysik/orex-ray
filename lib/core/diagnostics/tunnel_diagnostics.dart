import '../tunnel/tunnel_models.dart';

class TunnelDiagnostics {
  const TunnelDiagnostics({
    required this.platform,
    required this.xrayVersion,
    required this.mode,
    required this.targetName,
    required this.xrayState,
    required this.pid,
    required this.ports,
    required this.systemProxyStatus,
    required this.lastError,
    required this.lastExitCode,
    required this.outboundInterface,
    required this.restartSummary,
    required this.logs,
  });

  final String platform;
  final String xrayVersion;
  final ConnectionMode mode;
  final String targetName;
  final String xrayState;
  final int? pid;
  final Map<String, int> ports;
  final String systemProxyStatus;
  final String? lastError;
  final int? lastExitCode;
  final String? outboundInterface;
  final String restartSummary;
  final List<String> logs;
}

class DiagnosticSanitizer {
  const DiagnosticSanitizer._();

  static final _uuid = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b',
  );
  static final _vless = RegExp(r'''vless://[^\s"']+''');
  static final _secretJson = RegExp(
    r'''("?(?:id|password|privateKey|shortId|token|authorization)"?\s*[:=]\s*)["']?[^,}\]\s"']+''',
    caseSensitive: false,
  );
  static final _bearer = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+\-/=]+',
    caseSensitive: false,
  );

  static String sanitize(String input) {
    var value = input.replaceAll(_vless, 'vless://<REDACTED>');
    value = value.replaceAll(_uuid, '<UUID>');
    value = value.replaceAllMapped(
      _secretJson,
      (match) => '${match.group(1)}<REDACTED>',
    );
    value = value.replaceAll(_bearer, 'Bearer <REDACTED>');
    return value;
  }
}
