import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/widgets/orex_adaptive_header.dart';

void main() {
  testWidgets('header actions expand and collapse captions left-first',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget buildHeader() => MaterialApp(
      theme: OrexTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: OrexAdaptiveHeader(
            title: 'Профили',
            subtitle: 'Пример длинного пояснения заголовка',
            icon: Icons.dns_rounded,
            actions: [
              OrexHeaderAction(
                tooltip: 'Первое', label: 'Первое действие',
                icon: Icons.add_rounded, onPressed: () {},
              ),
              OrexHeaderAction(
                tooltip: 'Второе', label: 'Второе действие',
                icon: Icons.edit_rounded, onPressed: () {},
              ),
              OrexHeaderAction(
                tooltip: 'Третье', label: 'Третье действие',
                icon: Icons.check_rounded, onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(buildHeader());
    await tester.pumpAndSettle();
    expect(find.text('Первое действие'), findsOneWidget);
    expect(find.text('Второе действие'), findsOneWidget);
    expect(find.text('Третье действие'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(700, 700));
    await tester.pumpAndSettle();
    // Rightmost captions are retained longer than leftmost captions.
    expect(find.text('Первое действие'), findsNothing);
    expect(find.text('Третье действие'), findsOneWidget);
    expect(find.byTooltip('Первое'), findsOneWidget);
    expect(tester.getRect(find.byTooltip('Первое')).top,
        closeTo(tester.getRect(find.byTooltip('Третье')).top, 1));
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(280, 700));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Первое'), findsOneWidget);
    expect(find.byTooltip('Второе'), findsOneWidget);
    expect(find.byTooltip('Третье'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics-style actions use the same icons and layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(780, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: OrexAdaptiveHeader(
            title: 'Диагностика',
            subtitle: 'Состояние Xray, watchdog, маршруты и журнал',
            icon: Icons.monitor_heart_outlined,
            actions: [
              OrexHeaderAction(
                tooltip: 'Обновить диагностику', label: 'Обновить',
                icon: Icons.refresh_rounded, onPressed: () { refreshes++; },
              ),
              const OrexHeaderAction(
                tooltip: 'Скопировать отчёт', label: 'Скопировать отчёт',
                icon: Icons.copy_rounded, onPressed: null,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('Обновить диагностику'));
    await tester.pump();
    expect(refreshes, 1);
    expect(find.byTooltip('Скопировать отчёт'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
