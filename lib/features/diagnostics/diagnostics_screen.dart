import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/theme/orex_palette.dart';
import '../../shared/widgets/orex_adaptive_header.dart';
import '../../shared/widgets/orex_confirm_dialog.dart';
import '../../shared/widgets/orex_notice.dart';
import '../../shared/widgets/settings_section.dart';
import '../home/tunnel_controller.dart';
import '../../shared/l10n/orex_l10n.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.tunnel,
    required this.settings,
    required this.appVersion,
  });

  final TunnelController tunnel;
  final ConnectionSettingsController settings;
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
    // A diagnostics refresh is an explicit user request, so it is also a
    // valid event-driven opportunity to refresh the active exit location.
    unawaited(widget.tunnel.refreshEgressIdentity());
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
    final ports =
        value.ports.entries.map((e) => '${e.key} ${e.value}').join(' · ');
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
      'TUN route: ${value.routeSummary}',
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
    OrexNotice.show(
      context,
      SnackBar(content: Text('Diagnostic report copied'.tr)),
    );
  }

  Future<void> _setLogLevel(String value) async {
    if (value == 'info' || value == 'debug') {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => OrexConfirmDialog(
              icon: Icons.visibility_outlined,
              title: 'Verbose network logs'.tr,
              content: Text(
                'At "Information" and "Debug" levels Xray may log destination addresses and other network diagnostics. Use these modes only temporarily while troubleshooting.'.tr,
              ),
              confirmLabel: 'Enable'.tr,
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    await widget.settings.setLogLevel(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = _diagnostics;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _DiagnosticsHeader(
          loading: _loading,
          canCopy: value != null,
          onRefresh: _refresh,
          onCopy: _copy,
        ),
        const SizedBox(height: 20),
        SettingsSection(
          title: 'Log'.tr,
          subtitle: 'Xray level and OrexRay service events.'.tr,
          children: [
            ListTile(
              leading:
                  Icon(Icons.terminal_rounded, color: OrexPalette.of(context).accent),
              title: Text('Log level'.tr),
              subtitle: Text(_logLevelTitle(widget.settings.logLevel)),
              trailing: DropdownButton<String>(
                value: widget.settings.logLevel,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'error', child: Text('Errors'.tr)),
                  DropdownMenuItem(
                    value: 'warning',
                    child: Text('Warnings'.tr),
                  ),
                  DropdownMenuItem(value: 'info', child: Text('Information'.tr)),
                  DropdownMenuItem(value: 'debug', child: Text('Debug'.tr)),
                ],
                onChanged: (next) {
                  if (next != null) _setLogLevel(next);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          GlassPanel(
            borderRadius: 20,
            tint: OrexColors.danger,
            opacity: 0.14,
            padding: const EdgeInsets.all(16),
            child: Text('Failed to collect diagnostics: {}'.trf([_error])),
          )
        else if (value == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          SettingsSection(
            title: 'Status'.tr,
            subtitle: 'Current runtime picture without connection secrets.'.tr,
            children: [
              _DiagnosticRow(
                label: 'OrexRay',
                value: widget.appVersion.settingsSubtitle,
              ),
              _DiagnosticRow(label: 'Xray', value: value.xrayVersion),
              _DiagnosticRow(label: 'Mode'.tr, value: value.mode.title),
              _DiagnosticRow(label: 'Profile'.tr, value: value.targetName),
              _DiagnosticRow(label: 'Xray status'.tr, value: value.xrayState),
              _DiagnosticRow(label: 'PID', value: value.pid?.toString() ?? '—'),
              _DiagnosticRow(
                label: 'Ports'.tr,
                value: value.ports.entries
                    .map((e) => '${e.key} ${e.value}')
                    .join(' · '),
              ),
              _DiagnosticRow(
                label: 'System proxy'.tr,
                value: value.systemProxyStatus,
              ),
              _DiagnosticRow(
                label: 'Physical interface'.tr,
                value: value.outboundInterface ?? '—',
              ),
              _DiagnosticRow(label: 'TUN route'.tr, value: value.routeSummary),
              _DiagnosticRow(label: 'Watchdog', value: value.restartSummary),
              _DiagnosticRow(
                label: 'Last exit code'.tr,
                value: value.lastExitCode?.toString() ?? '—',
              ),
              _DiagnosticRow(
                label: 'Last error'.tr,
                value: value.lastError ?? '—',
              ),
              if (Platform.isWindows && value.mode == ConnectionMode.vpnTun)
                ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Windows network icon'.tr),
                  subtitle: Text(
                    'NCSI may show "No internet access" specifically for the virtual TUN adapter. The "TUN route" check above shows the actual best Windows route.'.tr,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Last {} log lines'.trf([value.logs.length]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SelectableText(
                  value.logs.isEmpty
                      ? 'The log is empty so far.'.tr
                      : value.logs.join('\n'),
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

class _DiagnosticsHeader extends StatelessWidget {
  const _DiagnosticsHeader({
    required this.loading,
    required this.canCopy,
    required this.onRefresh,
    required this.onCopy,
  });

  final bool loading;
  final bool canCopy;
  final VoidCallback onRefresh;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return OrexAdaptiveHeader(
      title: 'Diagnostics'.tr,
      subtitle: 'Xray status, watchdog, routes and safe log'.tr,
      icon: Icons.monitor_heart_outlined,
      actions: [
        OrexHeaderAction(
          tooltip: 'Refresh diagnostics'.tr,
          label: 'Update'.tr,
          icon: Icons.refresh_rounded,
          busy: loading,
          onPressed: loading ? null : onRefresh,
        ),
        OrexHeaderAction(
          tooltip: 'Copy report'.tr,
          label: 'Copy report'.tr,
          icon: Icons.copy_rounded,
          onPressed: canCopy ? onCopy : null,
        ),
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

String _logLevelTitle(String value) => switch (value) {
      'warning' => 'Warnings'.tr,
      'info' => 'Information'.tr,
      'debug' => 'Debug'.tr,
      _ => 'Errors only'.tr,
    };
