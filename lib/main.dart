import 'package:flutter/material.dart';

import 'app/orex_ray_app.dart';
import 'core/profiles/profiles_controller.dart';
import 'core/settings/connection_settings_controller.dart';
import 'shared/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = await Future.wait([
    ThemeController.load(),
    ProfilesController.load(),
    ConnectionSettingsController.load(),
  ]);
  runApp(
    OrexRayApp(
      theme: results[0] as ThemeController,
      profiles: results[1] as ProfilesController,
      connectionSettings: results[2] as ConnectionSettingsController,
    ),
  );
}
