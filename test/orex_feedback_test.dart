import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/shared/theme/glass.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:orex_ray/shared/widgets/orex_confirm_dialog.dart';
import 'package:orex_ray/shared/widgets/orex_notice.dart';

void main() {
  testWidgets('LAN confirmation stays compact on a wide desktop window',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const OrexConfirmDialog(
                title: 'Открыть прокси в локальную сеть?',
                content: Text('SOCKS5 и HTTP-прокси не требуют пароль.'),
                confirmLabel: 'Открыть доступ',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            child: const Text('Настроить LAN'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Настроить LAN'));
    await tester.pumpAndSettle();
    expect(find.byType(OrexConfirmDialog), findsOneWidget);
    // Dialog itself can occupy the route's full width; the actual visible
    // surface is constrained. Measure the layout child, not the route wrapper.
    expect(
      tester.getSize(find.byKey(const ValueKey('orex-confirm-content'))).width,
      lessThanOrEqualTo(561),
    );
    expect(find.byType(GlassPanel), findsNothing);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(OrexConfirmDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation remains opaque when glass is disabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark.copyWith(
        extensions: const [OrexGlassAppearance(enabled: false)],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const OrexConfirmDialog(
                title: 'Подтвердить',
                content: Text('Проверка'),
                confirmLabel: 'Да',
              ),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.byType(OrexConfirmDialog), findsOneWidget);
    expect(find.byType(GlassPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Да'));
    await tester.pumpAndSettle();
    expect(find.byType(OrexConfirmDialog), findsNothing);
  });

  testWidgets('a new bottom notification immediately replaces the previous',
      (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            homeContext = context;
            return const Text('Главная');
          },
        ),
      ),
    ));
    OrexNotice.copied(homeContext, 'SOCKS5 скопирован');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SOCKS5 скопирован'), findsOneWidget);

    OrexNotice.copied(homeContext, 'HTTP скопирован');
    OrexNotice.copied(homeContext, 'Новый адрес скопирован');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Новый адрес скопирован'), findsOneWidget);
    expect(find.text('SOCKS5 скопирован'), findsNothing);
    expect(find.text('HTTP скопирован'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
