import 'package:flutter/material.dart';

import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/egress_avatar.dart';
import '../../shared/widgets/orex_choice_sheet.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../../shared/widgets/status_pill.dart';
import 'tunnel_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.tunnel,
    this.active = true,
  });

  final TunnelController tunnel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: tunnel,
      builder: (context, _) {
        final snapshot = tunnel.snapshot;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    tunnel: tunnel,
                    snapshot: snapshot,
                    showStatus: wide,
                  ),
                  const SizedBox(height: 20),
                  if (snapshot.errorMessage != null) ...[
                    _ErrorCard(message: snapshot.errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  _ModeSelector(tunnel: tunnel),
                  const SizedBox(height: 16),
                  if (wide) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _ConnectionHero(
                            tunnel: tunnel,
                            snapshot: snapshot,
                            onTap: tunnel.toggle,
                            showStatusText: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _QuickInfo(
                            tunnel: tunnel,
                            snapshot: snapshot,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _TrafficCard(tunnel: tunnel, snapshot: snapshot),
                  ] else ...[
                    _ConnectionHero(
                      tunnel: tunnel,
                      snapshot: snapshot,
                      onTap: tunnel.toggle,
                      showStatusText: false,
                    ),
                    const SizedBox(height: 12),
                    _MobileStatusCard(tunnel: tunnel, snapshot: snapshot),
                    const SizedBox(height: 16),
                    _QuickInfo(tunnel: tunnel, snapshot: snapshot),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tunnel,
    required this.snapshot,
    required this.showStatus,
  });

  final TunnelController tunnel;
  final TunnelSnapshot snapshot;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      children: [
        const SquirrelMascot(size: 50, compact: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OrexRay', style: Theme.of(context).textTheme.headlineSmall),
              Text(
                'Xray-клиент с характером Orex',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );

    if (!showStatus) return brand;
    final profile = snapshot.profile;
    final pingStatus = snapshot.isConnected
        ? tunnel.effectivePingStatusFor(profile)
        : PingStatus.unknown;
    final routeFailed = _routeFailed(pingStatus);
    final label = routeFailed
        ? _routeFailureTitle(pingStatus)
        : switch (snapshot.status) {
            TunnelStatus.connected => 'Защищено',
            TunnelStatus.connecting => 'Подключение',
            TunnelStatus.disconnecting => 'Отключение',
            TunnelStatus.error => 'Ошибка',
            TunnelStatus.disconnected => 'Не подключено',
          };
    return Row(
      children: [
        Expanded(child: brand),
        const SizedBox(width: 16),
        StatusPill(
          label: label,
          active: snapshot.isConnected && !routeFailed,
          color: routeFailed ? OrexColors.dangerStrong : null,
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 20,
      tint: OrexColors.danger,
      opacity: 0.14,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: OrexColors.danger),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.tunnel});

  final TunnelController tunnel;

  @override
  Widget build(BuildContext context) {
    final modes = tunnel.supportedModes.toList(growable: false);
    if (modes.length < 2) return const SizedBox.shrink();

    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            child: Row(
              children: [
                const Icon(Icons.route_rounded,
                    size: 19, color: OrexColors.copper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Как направлять трафик',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!tunnel.canChangeMode)
                  Text('Сначала отключитесь',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ConnectionMode>(
              segments: [
                for (final mode in modes)
                  ButtonSegment<ConnectionMode>(
                    value: mode,
                    icon: Icon(
                      _modeIcon(mode),
                      color: tunnel.mode == mode ? OrexColors.copper : null,
                      size: 20,
                    ),
                    label: Text(mode.shortTitle),
                    tooltip: mode.description,
                  ),
              ],
              selected: {tunnel.mode},
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  final color = Theme.of(context).colorScheme.onSurface;
                  return states.contains(WidgetState.disabled)
                      ? color.withValues(alpha: 0.48)
                      : color;
                }),
                textStyle: WidgetStateProperty.resolveWith((states) {
                  return Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: states.contains(WidgetState.selected)
                            ? FontWeight.w700
                            : FontWeight.w500,
                      );
                }),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return OrexColors.copper.withValues(alpha: 0.24);
                  }
                  return Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.28);
                }),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Colors.transparent),
                ),
              ),
              onSelectionChanged: tunnel.canChangeMode
                  ? (selection) => tunnel.setMode(selection.first)
                  : null,
              showSelectedIcon: false,
              multiSelectionEnabled: false,
            ),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(tunnel.mode.description,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.tunnel,
    required this.snapshot,
    required this.onTap,
    required this.showStatusText,
  });

  final TunnelController tunnel;
  final TunnelSnapshot snapshot;
  final Future<void> Function() onTap;
  final bool showStatusText;

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;
    final active = snapshot.isConnected;
    final hasProfile = profile != null;
    final pingStatus = active
        ? tunnel.effectivePingStatusFor(profile)
        : PingStatus.unknown;
    final routeFailed = _routeFailed(pingStatus);

    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          if (showStatusText) ...[
            Text(
              routeFailed ? _routeFailureTitle(pingStatus) : _statusTitle(snapshot.status),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
          ],
          Text(
            snapshot.message ??
                (hasProfile
                    ? 'Готовы подключить ${profile.name}'
                    : 'Сначала добавьте профиль'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          _ConnectButton(
            snapshot: snapshot,
            pingStatus: pingStatus,
            enabled: hasProfile || snapshot.isConnected,
            onTap: onTap,
          ),
          const SizedBox(height: 24),
          Text(
            active
                ? _formatDuration(snapshot.stats.duration)
                : hasProfile
                    ? profile.endpoint
                    : 'Белочка пока без маршрута',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.snapshot,
    required this.pingStatus,
    required this.enabled,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final PingStatus pingStatus;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.isConnected;
    final busy = snapshot.isBusy;
    final canTap = enabled && !busy;
    final routeFailed = active && _routeFailed(pingStatus);
    final pingConfirmed = active && pingStatus == PingStatus.success;
    final healthConfirmed = routeFailed || pingConfirmed;
    final glowColor = routeFailed
        ? OrexColors.dangerStrong
        : pingConfirmed
            ? OrexColors.online
            : OrexColors.copper;
    return Semantics(
      button: true,
      enabled: canTap,
      label: active
          ? routeFailed
              ? 'Отключить OrexRay, маршрут не отвечает'
              : 'Отключить OrexRay'
          : 'Подключить OrexRay',
      child: GestureDetector(
        onTap: canTap ? () => onTap() : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: OrexColors.copperGradient,
              border: Border.all(
                // Timeout deliberately keeps the exact same cream ring and
                // geometry as a healthy connection. Only the ambient glow
                // changes hue, so red reads as a state rather than a second
                // button design.
                color: OrexColors.cream.withValues(
                  alpha: healthConfirmed
                      ? 0.65
                      : active
                          ? 0.48
                          : 0.28,
                ),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(
                    alpha: routeFailed
                        ? 0.58
                        : pingConfirmed
                            ? 0.32
                            : 0.22,
                  ),
                  blurRadius: healthConfirmed ? 52 : 30,
                  spreadRadius: healthConfirmed ? 4 : 0,
                ),
              ],
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: OrexColors.cream,
                      ),
                    )
                  : Icon(
                      active
                          ? Icons.power_settings_new_rounded
                          : Icons.power_rounded,
                      color: OrexColors.cream,
                      size: 68,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileStatusCard extends StatelessWidget {
  const _MobileStatusCard({required this.tunnel, required this.snapshot});

  final TunnelController tunnel;
  final TunnelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final pingLabel = _pingLabel(tunnel, snapshot.profile);
    return GlassPanel(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompactMetric(
                  icon: Icons.south_rounded,
                  label: 'Скачивание',
                  value: _speed(snapshot.stats.downloadBytesPerSecond),
                ),
              ),
              const SizedBox(height: 48, child: VerticalDivider()),
              Expanded(
                child: _CompactMetric(
                  icon: Icons.north_rounded,
                  label: 'Отдача',
                  value: _speed(snapshot.stats.uploadBytesPerSecond),
                ),
              ),
              const SizedBox(height: 48, child: VerticalDivider()),
              Expanded(
                child: _CompactMetric(
                  icon: Icons.network_ping_rounded,
                  label: 'Пинг',
                  value: pingLabel,
                  busy: tunnel.refreshingLatency,
                  onTap: snapshot.profile == null
                      ? null
                      : tunnel.refreshSelectedLatency,
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          Row(
            children: [
              const Icon(Icons.data_usage_rounded, color: OrexColors.copper),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Трафик',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              Flexible(
                child: Text(
                  '${_bytes(snapshot.stats.downloadBytes)} ↓ · '
                  '${_bytes(snapshot.stats.uploadBytes)} ↑',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Future<void> Function()? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          Icon(icon, color: OrexColors.copper, size: 20),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: busy ? null : () => onTap!(),
      child: child,
    );
  }
}

class _QuickInfo extends StatelessWidget {
  const _QuickInfo({required this.tunnel, required this.snapshot});

  final TunnelController tunnel;
  final TunnelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;
    final pingLabel = _pingLabel(tunnel, profile);
    return Column(
      children: [
        GlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: profile == null
              ? const _NoProfileCard()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap:
                            tunnel.canChangeTarget && tunnel.targets.length > 1
                                ? () => _showTargetPicker(context)
                                : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              EgressAvatar(
                                identity: tunnel.egressIdentityFor(profile.id),
                                fallbackIcon: profile.isBalancer
                                    ? Icons.hub_rounded
                                    : Icons.public_rounded,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            profile.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        if (tunnel.targets.length > 1)
                                          const Icon(Icons
                                              .keyboard_arrow_down_rounded),
                                      ],
                                    ),
                                    Text(
                                      profile.endpoint,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 18),
                    _InfoRow(label: 'Протокол', value: profile.protocol),
                    const SizedBox(height: 12),
                    _InfoRow(label: 'Транспорт', value: profile.transportLabel),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Задержка',
                      value: pingLabel,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              _CardIcon(icon: _modeIcon(snapshot.mode)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Текущий режим'),
                    const SizedBox(height: 3),
                    Text(snapshot.mode.description),
                  ],
                ),
              ),
              const Icon(Icons.lock_rounded, color: OrexColors.copper),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showTargetPicker(BuildContext context) async {
    final selectedId = snapshot.profile?.id;
    final id = await showOrexChoiceSheet<String>(
      context,
      title: 'Быстрая смена профиля',
      options: [
        for (final target in tunnel.targets)
          OrexChoiceSheetOption<String>(
            value: target.id,
            icon: target.isBalancer ? Icons.hub_rounded : Icons.public_rounded,
            title: target.name,
            subtitle: '${target.endpoint} · '
                '${tunnel.effectiveLatencyFor(target) == null ? 'Пинг —' : '${tunnel.effectiveLatencyFor(target)} мс'}',
            selected: selectedId == target.id,
          ),
      ],
    );
    if (id != null) await tunnel.selectTarget(id);
  }
}

class _NoProfileCard extends StatelessWidget {
  const _NoProfileCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SquirrelMascot(size: 70, compact: true),
        const SizedBox(height: 14),
        Text('Нет активного профиля',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          'Откройте вкладку «Профили» и импортируйте или создайте профиль',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.tunnel, required this.snapshot});

  final TunnelController tunnel;
  final TunnelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final pingLabel = _pingLabel(tunnel, snapshot.profile);
    return GlassPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              icon: Icons.south_rounded,
              label: 'Скачивание',
              value: _speed(snapshot.stats.downloadBytesPerSecond),
            ),
          ),
          const SizedBox(height: 54, child: VerticalDivider()),
          Expanded(
            child: _Metric(
              icon: Icons.north_rounded,
              label: 'Отдача',
              value: _speed(snapshot.stats.uploadBytesPerSecond),
            ),
          ),
          const SizedBox(height: 54, child: VerticalDivider()),
          Expanded(
            child: _Metric(
              icon: Icons.data_usage_rounded,
              label: 'Трафик',
              value: '${_bytes(snapshot.stats.downloadBytes)} ↓ · '
                  '${_bytes(snapshot.stats.uploadBytes)} ↑',
            ),
          ),
          const SizedBox(height: 54, child: VerticalDivider()),
          Expanded(
            child: _Metric(
              icon: Icons.network_ping_rounded,
              label: 'Пинг',
              value: pingLabel,
              busy: tunnel.refreshingLatency,
              onTap: snapshot.profile == null
                  ? null
                  : tunnel.refreshSelectedLatency,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Future<void> Function()? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: OrexColors.copper),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: busy ? null : () => onTap!(),
      child: child,
    );
  }
}

class _CardIcon extends StatelessWidget {
  const _CardIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: OrexColors.copper.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: OrexColors.copper),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

String _pingLabel(TunnelController tunnel, TunnelTarget? target) {
  final status = tunnel.effectivePingStatusFor(target);
  if (status != PingStatus.success) return '—';
  final ping = tunnel.effectiveLatencyFor(target);
  return ping == null ? '—' : '$ping мс';
}

bool _routeFailed(PingStatus status) =>
    status == PingStatus.timeout || status == PingStatus.unavailable;

String _routeFailureTitle(PingStatus status) => switch (status) {
      PingStatus.timeout => 'Таймаут',
      PingStatus.unavailable => 'Нет ответа',
      _ => 'Нет ответа',
    };

String _statusTitle(TunnelStatus status) => switch (status) {
      TunnelStatus.disconnected => 'Не подключено',
      TunnelStatus.connecting => 'Подключаем…',
      TunnelStatus.connected => 'OrexRay работает',
      TunnelStatus.disconnecting => 'Отключаем…',
      TunnelStatus.error => 'Ошибка подключения',
    };

String _formatDuration(Duration value) {
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _speed(int value) => '${_bytes(value)}/с';

String _bytes(int value) {
  if (value < 1024) return '$value Б';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} КБ';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
}

IconData _modeIcon(ConnectionMode mode) => switch (mode) {
      ConnectionMode.vpnTun => Icons.shield_rounded,
      ConnectionMode.systemProxy => Icons.desktop_windows_rounded,
      ConnectionMode.localProxy => Icons.code_rounded,
    };
