import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      widget.controller.loadApps();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.controller.supported) {
          return const _UnsupportedAppsScreen();
        }
        final query = _query.trim().toLowerCase();
        final apps = widget.controller.apps.where((app) {
          if (query.isEmpty) return true;
          return app.label.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
        }).toList(growable: false);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsPageHeader(
              title: 'Приложения',
              subtitle: 'Split tunneling: исключения или только выбранные приложения',
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
                    if (mode != null) widget.controller.setMode(mode);
                  },
                  child: Column(
                    children: [
                      for (final mode in AppRoutingMode.values)
                        RadioListTile<AppRoutingMode>(
                          value: mode,
                          secondary: Icon(_modeIcon(mode), color: OrexColors.copper),
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
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Поиск приложения или пакета',
                  suffixIcon: IconButton(
                    tooltip: 'Обновить список',
                    onPressed: widget.controller.loading
                        ? null
                        : () => widget.controller.loadApps(force: true),
                    icon: widget.controller.loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
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
              '${widget.controller.selectedPackages.length} выбрано · ${widget.controller.apps.length} найдено',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (widget.controller.loading && widget.controller.apps.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(36),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (apps.isEmpty)
              const GlassPanel(
                borderRadius: 20,
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Приложения не найдены')),
              )
            else
              GlassPanel(
                borderRadius: 20,
                child: Column(
                  children: [
                    for (var index = 0; index < apps.length; index++) ...[
                      CheckboxListTile(
                        value: widget.controller.selectedPackages
                            .contains(apps[index].packageName),
                        onChanged: (_) => widget.controller
                            .togglePackage(apps[index].packageName),
                        secondary: const CircleAvatar(
                          child: Icon(Icons.android_rounded, size: 19),
                        ),
                        title: Text(apps[index].label),
                        subtitle: Text(
                          apps[index].packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (index != apps.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
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
          subtitle: 'Split tunneling на уровне приложений доступен в Android VPN mode',
          icon: Icons.apps_rounded,
        ),
        SizedBox(height: 22),
        GlassPanel(
          borderRadius: 20,
          padding: EdgeInsets.all(24),
          child: Text('На Windows используйте системный прокси, локальный прокси или правила Xray. Список Android-приложений здесь недоступен.'),
        ),
      ],
    );
  }
}

IconData _modeIcon(AppRoutingMode mode) => switch (mode) {
      AppRoutingMode.all => Icons.select_all_rounded,
      AppRoutingMode.excludeSelected => Icons.remove_circle_outline_rounded,
      AppRoutingMode.onlySelected => Icons.check_circle_outline_rounded,
    };
