import 'package:flutter/material.dart';

import '../../core/tunnel/tunnel_models.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/squirrel_mascot.dart';
import '../../shared/widgets/status_pill.dart';
import 'tunnel_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.tunnel});

  final TunnelController tunnel;

  @override
  Widget build(BuildContext context) {
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(snapshot: snapshot),
                  const SizedBox(height: 20),
                  if (snapshot.errorMessage != null) ...[
                    _ErrorCard(message: snapshot.errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  _ModeSelector(tunnel: tunnel),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _ConnectionHero(
                            snapshot: snapshot,
                            onTap: tunnel.toggle,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _QuickInfo(snapshot: snapshot),
                        ),
                      ],
                    )
                  else ...[
                    _ConnectionHero(snapshot: snapshot, onTap: tunnel.toggle),
                    const SizedBox(height: 16),
                    _QuickInfo(snapshot: snapshot),
                  ],
                  const SizedBox(height: 16),
                  _TrafficCard(snapshot: snapshot),
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
  const _Header({required this.snapshot});

  final TunnelSnapshot snapshot;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final label = switch (snapshot.status) {
          TunnelStatus.connected => 'Защищено',
          TunnelStatus.connecting => 'Подключение',
          TunnelStatus.disconnecting => 'Отключение',
          TunnelStatus.error => 'Ошибка',
          TunnelStatus.disconnected => 'Не подключено',
        };
        final pill = StatusPill(label: label, active: snapshot.isConnected);
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [brand, const SizedBox(height: 12), pill],
          );
        }
        return Row(
          children: [
            Expanded(child: brand),
            const SizedBox(width: 16),
            pill,
          ],
        );
      },
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
                const Icon(Icons.route_rounded, size: 19, color: OrexColors.copper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Как направлять трафик',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!tunnel.canChangeMode)
                  Text(
                    'Сначала отключитесь',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
                    icon: Icon(_modeIcon(mode)),
                    label: Text(mode.shortTitle),
                    tooltip: mode.description,
                  ),
              ],
              selected: {tunnel.mode},
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
            child: Text(
              tunnel.mode.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({required this.snapshot, required this.onTap});

  final TunnelSnapshot snapshot;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;
    final active = snapshot.isConnected;
    final hasProfile = profile != null;

    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          Text(_statusTitle(snapshot.status),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            snapshot.message ??
                (hasProfile
                    ? 'Готовы подключить ${profile.name}'
                    : 'Сначала добавьте VLESS-профиль'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          _ConnectButton(
            snapshot: snapshot,
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
    required this.enabled,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.isConnected;
    final busy = snapshot.isBusy;
    final canTap = enabled && !busy;
    return Semantics(
      button: true,
      enabled: canTap,
      label: active ? 'Отключить OrexRay' : 'Подключить OrexRay',
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
                color: OrexColors.cream.withValues(alpha: active ? 0.65 : 0.28),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (active ? OrexColors.online : OrexColors.copper)
                      .withValues(alpha: 0.32),
                  blurRadius: active ? 52 : 32,
                  spreadRadius: active ? 4 : 0,
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

class _QuickInfo extends StatelessWidget {
  const _QuickInfo({required this.snapshot});

  final TunnelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;
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
                    Row(
                      children: [
                        const _CardIcon(icon: Icons.public_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(profile.endpoint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 18),
                    _InfoRow(label: 'Протокол', value: profile.protocol),
                    const SizedBox(height: 12),
                    _InfoRow(
                        label: 'Транспорт', value: profile.transportLabel),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Задержка',
                      value: profile.latencyMs == null
                          ? '—'
                          : '${profile.latencyMs} мс',
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
          'Откройте вкладку «Профили» и импортируйте vless://',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.snapshot});

  final TunnelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ping = snapshot.profile?.latencyMs;
    return GlassPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 620;
          final cards = [
            _Metric(
              icon: Icons.south_rounded,
              label: 'Скачивание',
              value: _speed(snapshot.stats.downloadBytesPerSecond),
            ),
            _Metric(
              icon: Icons.north_rounded,
              label: 'Отдача',
              value: _speed(snapshot.stats.uploadBytesPerSecond),
            ),
            _Metric(
              icon: Icons.data_usage_rounded,
              label: 'Трафик',
              value: '${_bytes(snapshot.stats.downloadBytes)} ↓ · ${_bytes(snapshot.stats.uploadBytes)} ↑',
            ),
            _Metric(
              icon: Icons.network_ping_rounded,
              label: 'Ping',
              value: ping == null ? '—' : '$ping мс',
            ),
          ];
          if (horizontal) {
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1)
                    const SizedBox(height: 54, child: VerticalDivider()),
                ],
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const Divider(height: 24),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: OrexColors.copper),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ],
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
