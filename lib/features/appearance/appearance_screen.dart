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
          const SettingsSection(
            title: 'Стиль',
            children: [
              ListTile(
                leading: Icon(Icons.blur_on_rounded),
                title: Text('Стеклянные панели'),
                subtitle: Text('Фирменный glassmorphism Orex включён всегда'),
              ),
              Divider(height: 1),
              ListTile(
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
