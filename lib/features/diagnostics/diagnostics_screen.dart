import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/diagnostics/tunnel_diagnostics.dart';
import '../../core/settings/connection_settings_controller.dart';
import '../../core/tunnel/tunnel_models.dart';
import '../../platform/windows/windows_elevation_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';
import '../home/tunnel_controller.dart';

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
  bool _repairingCore = false;
  double? _repairProgress;

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Диагностический отчёт скопирован')),
    );
  }

  Future<void> _reinstallXrayCore() async {
    if (_repairingCore) return;
    if (!widget.tunnel.canReinstallXrayCore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала отключи активное соединение.')),
      );
      return;
    }

    if (Platform.isWindows &&
        await WindowsElevationController.isProtectedInstall() &&
        !await WindowsElevationController.isElevated()) {
      if (!mounted) return;
      final restart = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Нужны права администратора'),
              content: const Text(
                'Xray Core установлен в Program Files. OrexRay перезапустится '
                'с правами администратора; после перезапуска снова открой '
                '«Диагностика» и нажми «Переустановить Xray Core».',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Перезапустить'),
                ),
              ],
            ),
          ) ??
          false;
      if (!restart) return;
      await WindowsElevationController.restartElevated();
      return;
    }

    setState(() {
      _repairingCore = true;
      _repairProgress = null;
    });
    try {
      await widget.tunnel.reinstallXrayCore(
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _repairProgress = value.clamp(0.0, 1.0).toDouble());
        },
      );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xray Core переустановлен и проверен.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переустановить Xray Core: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _repairingCore = false;
          _repairProgress = null;
        });
      }
    }
  }

  Future<void> _setLogLevel(String value) async {
    if (value == 'info' || value == 'debug') {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.visibility_outlined),
              title: const Text('Подробные сетевые логи'),
              content: const Text(
                'На уровнях «Информация» и «Отладка» Xray может писать адреса '
                'назначения и другую сетевую диагностику. Используй эти '
                'режимы только временно при поиске проблемы.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Включить'),
                ),
              ],
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
          title: 'Журнал',
          subtitle: 'Уровень Xray и служебные события OrexRay.',
          children: [
            ListTile(
              leading:
                  const Icon(Icons.terminal_rounded, color: OrexColors.copper),
              title: const Text('Уровень логов'),
              subtitle: Text(_logLevelTitle(widget.settings.logLevel)),
              trailing: DropdownButton<String>(
                value: widget.settings.logLevel,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'error', child: Text('Ошибки')),
                  DropdownMenuItem(
                    value: 'warning',
                    child: Text('Предупреждения'),
                  ),
                  DropdownMenuItem(value: 'info', child: Text('Информация')),
                  DropdownMenuItem(value: 'debug', child: Text('Отладка')),
                ],
                onChanged: (next) {
                  if (next != null) _setLogLevel(next);
                },
              ),
            ),
          ],
        ),
        if (Platform.isWindows) ...[
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Xray Core',
            subtitle: 'Восстановление закреплённой и проверенной версии Core.',
            children: [
              ListTile(
                leading: const Icon(
                  Icons.system_update_alt_rounded,
                  color: OrexColors.copper,
                ),
                title: const Text('Переустановить Xray Core'),
                subtitle: Text(
                  _repairingCore
                      ? _repairProgress == null
                          ? 'Подготавливаем восстановление…'
                          : 'Загрузка · ${(_repairProgress! * 100).round()}%'
                      : 'Восстанавливает xray.exe, wintun.dll и встроенные '
                          'GeoData из pinned-архива с проверкой SHA-256.',
                ),
                trailing: OutlinedButton.icon(
                  onPressed:
                      _repairingCore || !widget.tunnel.canReinstallXrayCore
                          ? null
                          : _reinstallXrayCore,
                  icon: _repairingCore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.build_circle_outlined),
                  label: const Text('Переустановить'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
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
              _DiagnosticRow(
                label: 'OrexRay',
                value: widget.appVersion.settingsSubtitle,
              ),
              _DiagnosticRow(label: 'Xray', value: value.xrayVersion),
              _DiagnosticRow(label: 'Режим', value: value.mode.title),
              _DiagnosticRow(label: 'Профиль', value: value.targetName),
              _DiagnosticRow(label: 'Состояние Xray', value: value.xrayState),
              _DiagnosticRow(label: 'PID', value: value.pid?.toString() ?? '—'),
              _DiagnosticRow(
                label: 'Порты',
                value: value.ports.entries
                    .map((e) => '${e.key} ${e.value}')
                    .join(' · '),
              ),
              _DiagnosticRow(
                label: 'Системный proxy',
                value: value.systemProxyStatus,
              ),
              _DiagnosticRow(
                label: 'Физический интерфейс',
                value: value.outboundInterface ?? '—',
              ),
              _DiagnosticRow(label: 'Маршрут TUN', value: value.routeSummary),
              _DiagnosticRow(label: 'Watchdog', value: value.restartSummary),
              _DiagnosticRow(
                label: 'Последний exit code',
                value: value.lastExitCode?.toString() ?? '—',
              ),
              _DiagnosticRow(
                label: 'Последняя ошибка',
                value: value.lastError ?? '—',
              ),
              if (Platform.isWindows && value.mode == ConnectionMode.vpnTun)
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Значок сети Windows'),
                  subtitle: Text(
                    'NCSI может показывать «Нет доступа к интернету» именно '
                    'для виртуального TUN-адаптера. Проверка «Маршрут TUN» '
                    'выше показывает фактический лучший маршрут Windows.',
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
                  'Последние ${value.logs.length} строк лога',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SelectableText(
                  value.logs.isEmpty
                      ? 'Журнал пока пуст.'
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
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Диагностика', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Состояние Xray, watchdog, маршруты и безопасный журнал',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: const Text('Обновить'),
        ),
        OutlinedButton.icon(
          onPressed: canCopy ? onCopy : null,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Скопировать отчёт'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 14),
            actions,
          ],
        );
      },
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
      'warning' => 'Предупреждения',
      'info' => 'Информация',
      'debug' => 'Отладка',
      _ => 'Только ошибки',
    };
