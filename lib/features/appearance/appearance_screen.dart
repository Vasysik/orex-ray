import 'package:flutter/material.dart';

import '../../shared/widgets/settings_section.dart';
import '../../shared/theme/theme_controller.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SettingsPageHeader(
            title: 'Интерфейс',
            subtitle: 'Внешний вид OrexRay и фирменная тема Orex',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 22),
          SettingsSection(
            title: 'Тема',
            children: [
              RadioGroup<ThemeMode>(
                groupValue: theme.mode,
                onChanged: (mode) {
                  if (mode != null) theme.setMode(mode);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      secondary: Icon(Icons.dark_mode_rounded),
                      title: Text('Тёмная'),
                      subtitle: Text('Фирменный тёмный Orex'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      secondary: Icon(Icons.light_mode_rounded),
                      title: Text('Светлая'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      secondary: Icon(Icons.brightness_auto_rounded),
                      title: Text('Системная'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Стиль',
            children: [
              SwitchListTile(
                key: const ValueKey('appearance-glass-toggle'),
                secondary: const Icon(Icons.blur_on_rounded),
                title: const Text('Стеклянные панели'),
                subtitle: const Text('Размытие и полупрозрачные поверхности'),
                value: theme.glassEnabled,
                onChanged: theme.setGlassEnabled,
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.pets_rounded),
                title: Text('Маскот'),
                subtitle: Text('Белочка остаётся частью экранов и загрузки'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
