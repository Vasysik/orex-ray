import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orex_ray/core/profiles/profiles_controller.dart';
import 'package:orex_ray/core/settings/connection_settings_controller.dart';
import 'package:orex_ray/core/tunnel/mock_tunnel_engine.dart';
import 'package:orex_ray/features/home/home_screen.dart';
import 'package:orex_ray/features/home/tunnel_controller.dart';
import 'package:orex_ray/shared/l10n/orex_l10n.dart';
import 'package:orex_ray/shared/theme/orex_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('system locale follows preferences and distinguishes Chinese scripts',
      () {
    const simplified =
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    expect(
        OrexL10n.resolveSystemLocale([const Locale('zh', 'CN')]), simplified);
    expect(
      OrexL10n.resolveSystemLocale(
        [const Locale('zh', 'TW'), const Locale('pl', 'PL')],
      ),
      const Locale('pl'),
    );
    expect(
        OrexL10n.resolveSystemLocale([const Locale('de')]), const Locale('en'));
    expect(
      OrexL10n.resolveSystemLocale([const Locale('ar', 'EG')]),
      const Locale('ar'),
    );
  });

  test('language survives reload and missing strings use English', () async {
    SharedPreferences.setMockInitialValues({'orex_ray_language': 'ru'});
    final l10n = await OrexL10n.load();
    expect('Home'.tr, 'Главная');

    await l10n.setLanguage('pl');
    expect((await OrexL10n.load()).language, 'pl');
    expect('Home'.tr, 'Start');
    expect('A feature with no translation'.tr, 'A feature with no translation');

    await OrexL10n.instance.setLanguage('zh');
    expect('Home'.tr, '主页');
    expect(OrexL10n.instance.plural(3, 'day'), '3天');
    expect(OrexL10n.instance.dayMonth(DateTime(2026, 11, 20)), '11月20日');

    await OrexL10n.instance.setLanguage('ar');
    expect('Home'.tr, 'الرئيسية');
    expect('Starting Xray Core…'.tr, 'جارٍ تشغيل Xray Core…');
    expect(OrexL10n.instance.plural(3, 'hour'), '3 ساعات');
  });

  test('substitution preserves braces within arguments', () {
    expect('x {} y {}'.trf(['{}', 'B']), 'x {} y B');
  });

  test('Polish and Russian quantities use the right forms', () async {
    SharedPreferences.setMockInitialValues({'orex_ray_language': 'pl'});
    final l10n = await OrexL10n.load();
    expect(l10n.plural(1, 'server'), '1 serwer');
    expect(l10n.plural(22, 'server'), '22 serwery');
    expect(l10n.plural(12, 'server'), '12 serwerów');
    await l10n.setLanguage('ru');
    expect(l10n.plural(21, 'server'), '21 сервер');
    expect(l10n.plural(22, 'server'), '22 сервера');
    expect(l10n.plural(12, 'server'), '12 серверов');
  });

  test('catalog entries preserve placeholders without requiring full coverage',
      () {
    for (final locale in OrexL10n.supportedLocales) {
      final language = locale.toLanguageTag();
      final entries = OrexL10n.catalogFor(locale);
      for (final MapEntry(:key, :value) in entries.entries) {
        expect(value.trim(), isNotEmpty, reason: '$language / $key');
        expect(
          '{}'.allMatches(value).length,
          '{}'.allMatches(key).length,
          reason: '$language / $key',
        );
      }
    }
  });

  testWidgets('Arabic home fits a narrow window and uses RTL', (tester) async {
    SharedPreferences.setMockInitialValues({'orex_ray_language': 'ar'});
    final l10n = await OrexL10n.load();
    final profiles = await ProfilesController.load();
    final settings = await ConnectionSettingsController.load(
      operatingSystem: 'android',
    );
    final tunnel = TunnelController(
      engine: MockTunnelEngine(),
      profiles: profiles,
      settings: settings,
    );
    addTearDown(() {
      tunnel.dispose();
      profiles.dispose();
      settings.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      theme: OrexTheme.dark,
      locale: l10n.locale,
      supportedLocales: OrexL10n.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomeScreen(tunnel: tunnel),
    ));
    await tester.pumpAndSettle();
    expect(find.text('لم يجد السنجاب مسارًا بعد'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(HomeScreen))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
