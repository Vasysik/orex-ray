import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/apps/app_routing_controller.dart';
import '../../shared/theme/glass.dart';
import '../../shared/theme/orex_theme.dart';
import '../../shared/widgets/settings_section.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, required this.controller});

  final AppRoutingController controller;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  String _query = '';
  bool _selectedOnly = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) unawaited(widget.controller.loadApps());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.controller.supported) return const _UnsupportedAppsScreen();

        final query = _query.trim().toLowerCase();
        final apps = widget.controller.apps.where((app) {
          if (!widget.controller.showSystemApps && app.isSystem) return false;
          if (_selectedOnly &&
              !widget.controller.selectedPackages.contains(app.packageName)) {
            return false;
          }
          if (query.isEmpty) return true;
          return app.label.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
        }).toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SettingsPageHeader(
                    title: 'Приложения',
                    subtitle:
                        'Split tunneling: исключения или только выбранные приложения',
                    icon: Icons.apps_rounded,
                  ),
                  const SizedBox(height: 22),
                  SettingsSection(
                    title: 'Режим',
                    subtitle: 'Применяется при следующем запуске Android VPN.',
                    children: [
                      RadioGroup<AppRoutingMode>(
                        groupValue: widget.controller.mode,
                        onChanged: (mode) {
                          if (mode != null) {
                            unawaited(widget.controller.setMode(mode));
                          }
                        },
                        child: Column(
                          children: [
                            for (final mode in AppRoutingMode.values)
                              RadioListTile<AppRoutingMode>(
                                value: mode,
                                secondary: Icon(
                                  _modeIcon(mode),
                                  color: OrexColors.copper,
                                ),
                                title: Text(mode.title),
                                subtitle: Text(mode.description),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Поиск приложения или пакета',
                            suffixIcon: IconButton(
                              tooltip: 'Обновить список',
                              onPressed: widget.controller.loading
                                  ? null
                                  : () => unawaited(
                                        widget.controller.loadApps(force: true),
                                      ),
                              icon: widget.controller.loading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              selected: widget.controller.showSystemApps,
                              avatar: const Icon(
                                Icons.settings_suggest_rounded,
                                size: 18,
                              ),
                              label: const Text('Системные'),
                              onSelected: (value) => unawaited(
                                widget.controller.setShowSystemApps(value),
                              ),
                            ),
                            FilterChip(
                              selected: _selectedOnly,
                              avatar: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Только выбранные'),
                              onSelected: (value) =>
                                  setState(() => _selectedOnly = value),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.controller.error != null) ...[
                    const SizedBox(height: 12),
                    GlassPanel(
                      borderRadius: 18,
                      tint: OrexColors.danger,
                      opacity: 0.14,
                      padding: const EdgeInsets.all(14),
                      child: Text(widget.controller.error!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '${widget.controller.selectedPackages.length} выбрано · '
                    '${apps.length} показано · ${widget.controller.apps.length} всего',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            if (widget.controller.loading && widget.controller.apps.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (apps.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: GlassPanel(
                    borderRadius: 20,
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Приложения не найдены')),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final app = apps[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GlassPanel(
                          borderRadius: 16,
                          padding: EdgeInsets.zero,
                          child: CheckboxListTile(
                            value: widget.controller.selectedPackages
                                .contains(app.packageName),
                            onChanged: (_) => unawaited(
                              widget.controller.togglePackage(app.packageName),
                            ),
                            secondary: _AppIcon(
                              app: app,
                              controller: widget.controller,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    app.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (app.isSystem)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Tooltip(
                                      message: 'Системное приложение',
                                      child: Icon(
                                        Icons.settings_rounded,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              app.packageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: apps.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.app, required this.controller});

  final AndroidAppInfo app;
  final AppRoutingController controller;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  late ValueListenable<Uint8List?> _icon;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName ||
        oldWidget.controller != widget.controller) {
      _bind();
    }
  }

  void _bind() {
    _icon = widget.controller.iconListenableFor(widget.app.packageName);
    unawaited(widget.controller.loadIcon(widget.app.packageName));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      child: ValueListenableBuilder<Uint8List?>(
        valueListenable: _icon,
        builder: (context, bytes, _) {
          if (bytes == null) {
            return const Icon(
              Icons.android_rounded,
              color: OrexColors.copper,
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              cacheWidth: 96,
              cacheHeight: 96,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.android_rounded,
                color: OrexColors.copper,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UnsupportedAppsScreen extends StatelessWidget {
  const _UnsupportedAppsScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SettingsPageHeader(
          title: 'Приложения',
          subtitle: 'Split tunneling по приложениям доступен на Android',
          icon: Icons.apps_rounded,
        ),
        SizedBox(height: 22),
        GlassPanel(
          borderRadius: 22,
          padding: EdgeInsets.all(24),
          child: Text(
            'На Windows маршрутизация по процессам потребует отдельного '
            'Windows-native backend. Сейчас эта страница управляет Android VPN.',
          ),
        ),
      ],
    );
  }
}

IconData _modeIcon(AppRoutingMode mode) => switch (mode) {
      AppRoutingMode.all => Icons.all_inclusive_rounded,
      AppRoutingMode.excludeSelected => Icons.remove_circle_outline_rounded,
      AppRoutingMode.onlySelected => Icons.filter_alt_rounded,
    };
