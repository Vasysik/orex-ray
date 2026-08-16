import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/features/network/network_screen.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'latency probe settings are in the dedicated Network screen',
    (tester) async {
      final settings = await _pumpNetworkScreen(tester);

      final sectionTitle = find.text('ПРОВЕРКА ЗАДЕРЖКИ');
      await tester.scrollUntilVisible(
        sectionTitle,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(sectionTitle);
      await tester.pumpAndSettle();

      expect(sectionTitle, findsOneWidget);
      expect(
        find.text('Публичный адрес для измерения задержки'),
        findsOneWidget,
      );

      final google = find.byWidgetPredicate(
        (widget) =>
            widget is RadioListTile<LatencyProbePreset> &&
            widget.value == LatencyProbePreset.google,
      );
      await tester.scrollUntilVisible(
        google,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(google);
      await tester.pumpAndSettle();
      expect(settings.latencyProbePreset, LatencyProbePreset.google);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'custom latency probe URL is edited from the dedicated Network screen',
    (tester) async {
      final settings = await _pumpNetworkScreen(tester);

      final custom = find.text('Свой URL');
      await tester.scrollUntilVisible(
        custom,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(custom);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(of: custom, matching: find.byType(ListTile)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField),
        'https://probe.example.com/health',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(settings.latencyProbePreset, LatencyProbePreset.custom);
      expect(
        settings.latencyProbeUri.toString(),
        'https://probe.example.com/health',
      );
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

Future<ConnectionSettingsController> _pumpNetworkScreen(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await ConnectionSettingsController.load(
    operatingSystem: 'android',
  );
  addTearDown(settings.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: OrexTheme.dark,
      home: NetworkScreen(settings: settings),
    ),
  );
  await tester.pump();

  return settings;
}
