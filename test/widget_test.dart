import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/app/orex_ray_app.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/shared/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('OrexRay starts with squirrel empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = await ThemeController.load();
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'linux',
    );

    await tester.pumpWidget(
      OrexRayApp(
        theme: theme,
        profiles: profiles,
        connectionSettings: settings,
      ),
    );
    await tester.pump();

    expect(find.text('OrexRay'), findsOneWidget);
    expect(find.text('Белочка пока без маршрута'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    profiles.dispose();
    settings.dispose();
    theme.dispose();
  });
}
