import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';
import '../home/tunnel_controller.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.tunnel,
    required this.appVersion,
  });

  final TunnelController tunnel;
  final OrexAppVersion appVersion;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  TunnelDiagnostics? _diagnostics;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.tunnel.collectDiagnostics();
      if (!mounted) return;
      setState(() => _diagnostics = value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _report(TunnelDiagnostics value) {
    final ports = value.ports.entries.map((e) => '${e.key} ${e.value}').join(' · ');
    final lines = <String>[
      'OrexRay diagnostics',
      'OrexRay: ${widget.appVersion.version}+${widget.appVersion.buildNumber}',
      'Platform: ${value.platform}',
      'Xray: ${value.xrayVersion}',
      'Mode: ${value.mode.storageValue}',
      'Target: ${value.targetName}',
      'State: ${value.xrayState}',
      'PID: ${value.pid ?? '—'}',
      'Ports: ${ports.isEmpty ? '—' : ports}',
      'System proxy: ${value.systemProxyStatus}',
      'Outbound interface: ${value.outboundInterface ?? '—'}',
      'Watchdog: ${value.restartSummary}',
      'Last exit code: ${value.lastExitCode ?? '—'}',
      'Last error: ${value.lastError ?? '—'}',
      '',
      'Last ${value.logs.length} log lines:',
      ...value.logs,
    ];
    return DiagnosticSanitizer.sanitize(lines.join('\n'));
  }

  Future<void> _copy() async {
    final value = _diagnostics;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: _report(value)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Диагностический отчёт скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _diagnostics;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsPageHeader(
          title: 'Диагностика',
          subtitle: 'Состояние Xray, watchdog, порты и безопасный журнал',
          icon: Icons.monitor_heart_outlined,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Обновить'),
            ),
            FilledButton.icon(
              onPressed: value == null ? null : _copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Скопировать отчёт'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (_error != null)
          GlassPanel(
            borderRadius: 20,
            tint: OrexColors.danger,
            opacity: 0.14,
            padding: const EdgeInsets.all(16),
            child: Text('Не удалось собрать диагностику: $_error'),
          )
        else if (value == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          SettingsSection(
            title: 'Состояние',
            subtitle: 'Текущая runtime-картина без секретов подключения.',
            children: [
              _DiagnosticRow(label: 'OrexRay', value: widget.appVersion.settingsSubtitle),
              _DiagnosticRow(label: 'Xray', value: value.xrayVersion),
              _DiagnosticRow(label: 'Режим', value: value.mode.title),
              _DiagnosticRow(label: 'Профиль', value: value.targetName),
              _DiagnosticRow(label: 'Состояние Xray', value: value.xrayState),
              _DiagnosticRow(label: 'PID', value: value.pid?.toString() ?? '—'),
              _DiagnosticRow(
                label: 'Порты',
                value: value.ports.entries.map((e) => '${e.key} ${e.value}').join(' · '),
              ),
              _DiagnosticRow(label: 'Системный proxy', value: value.systemProxyStatus),
              _DiagnosticRow(
                label: 'Физический интерфейс',
                value: value.outboundInterface ?? '—',
              ),
              _DiagnosticRow(label: 'Watchdog', value: value.restartSummary),
              _DiagnosticRow(
                label: 'Последний exit code',
                value: value.lastExitCode?.toString() ?? '—',
              ),
              _DiagnosticRow(label: 'Последняя ошибка', value: value.lastError ?? '—'),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Последние ${value.logs.length} строк лога',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SelectableText(
                  value.logs.isEmpty ? 'Журнал пока пуст.' : value.logs.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: SelectableText(value.isEmpty ? '—' : value),
    );
  }
}
