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
      expect(find.text('Интервал интерфейса'), findsOneWidget);
      expect(find.text('Интервал уведомления'), findsOneWidget);
      expect(find.text('Интервал пинга'), findsOneWidget);
      expect(
        find.textContaining('Как часто проверять активный маршрут'),
        findsOneWidget,
      );

      await tester.tap(find.text('Показывать уведомления'));
      await tester.pump();
      expect(openedSystemSettings, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.text('Автообновление подписок'), findsOneWidget);
      expect(find.text('Метаданные подписок'), findsOneWidget);
      expect(find.text('12 ч'), findsOneWidget);
      expect(find.text('10 мин'), findsOneWidget);

    },
  );
  testWidgets(
    'ping interval is visible on Windows without notification controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ConnectionSettingsController.load(
        operatingSystem: 'windows',
      );
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: OrexTheme.dark,
          home: BackgroundScreen(settings: settings, isAndroid: false),
        ),
      );
      await tester.pump();

      expect(find.text('Интервал интерфейса'), findsOneWidget);
      expect(find.text('Интервал пинга'), findsOneWidget);
      expect(find.text('Интервал уведомления'), findsNothing);
      expect(find.text('Показывать уведомления'), findsNothing);
      expect(
        find.text('Как часто проверять активный маршрут во время подключения.'),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('Автообновление подписок'), findsOneWidget);
      expect(find.text('Метаданные подписок'), findsOneWidget);
    },
  );
}
