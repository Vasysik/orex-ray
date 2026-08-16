import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/features/background/background_screen.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tunnelChannel = MethodChannel('ru.orex.ray/tunnel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(tunnelChannel, null);
  });

  testWidgets(
    'Android notification controls open system visibility settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ConnectionSettingsController.load(
        operatingSystem: 'android',
      );
      addTearDown(settings.dispose);
      var openedSystemSettings = false;
      messenger.setMockMethodCallHandler(tunnelChannel, (call) async {
        if (call.method == 'openNotificationSettings') {
          openedSystemSettings = true;
        }
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: OrexTheme.dark,
          home: BackgroundScreen(settings: settings, isAndroid: true),
        ),
      );
      await tester.pump();

      expect(find.text('Показывать уведомления'), findsOneWidget);
      expect(
        find.text('Видимость меняется в системных настройках Android.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.swipe_rounded), findsNothing);

      await tester.tap(find.text('Показывать уведомления'));
      await tester.pump();
      expect(openedSystemSettings, isTrue);
    },
  );
}
