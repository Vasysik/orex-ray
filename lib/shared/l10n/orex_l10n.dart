import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'orex_l10n_ar.dart';
import 'orex_l10n_pl.dart';
import 'orex_l10n_ru.dart';
import 'orex_l10n_zh.dart';

/// English source strings are the translation keys and the fallback.
class OrexL10n extends ChangeNotifier {
  OrexL10n._(this._language);

  static const _languageKey = 'orex_ray_language';
  static const _catalogs = <String,
      ({String name, Locale locale, Map<String, String> translations})>{
    'en': (name: 'English', locale: Locale('en'), translations: {}),
    'ru': (name: 'Русский', locale: Locale('ru'), translations: orexL10nRu),
    'pl': (name: 'Polski', locale: Locale('pl'), translations: orexL10nPl),
    'zh': (
      name: '简体中文',
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      translations: orexL10nZh,
    ),
    'ar': (name: 'العربية', locale: Locale('ar'), translations: orexL10nAr),
  };

  static final supportedLocales = List<Locale>.unmodifiable(
    _catalogs.values.map((catalog) => catalog.locale),
  );

  static Map<String, String> get languageNames => {
        'system': tr('Same as system'),
        for (final entry in _catalogs.entries) entry.key: entry.value.name,
      };

  static bool _supports(String? language) =>
      language == 'system' || _catalogs.containsKey(language);

  static OrexL10n? _instance;

  /// Null before [load] completes; the launch splash tolerates that.
  static OrexL10n? get instanceOrNull => _instance;

  /// Legacy Russian default for code called before bootstrap and test fixtures.
  static OrexL10n get instance => _instance ??= OrexL10n._('ru');

  String _language;
  String get language => _language;

  Locale get locale => _language == 'system'
      ? resolveSystemLocale(WidgetsBinding.instance.platformDispatcher.locales)
      : _catalogs[_language]!.locale;

  static Locale resolveSystemLocale(Iterable<Locale> preferredLocales) {
    for (final preferred in preferredLocales) {
      final catalog = _catalogs[preferred.languageCode];
      if (catalog == null) continue;
      if (preferred.languageCode == 'zh') {
        final script = preferred.scriptCode ??
            (const {'TW', 'HK', 'MO'}.contains(preferred.countryCode)
                ? 'Hant'
                : 'Hans');
        if (script != catalog.locale.scriptCode) continue;
      }
      return catalog.locale;
    }
    return _catalogs['en']!.locale;
  }

  static Future<OrexL10n> load() async {
    final prefs = await SharedPreferences.getInstance();
    await initializeDateFormatting();
    final stored = prefs.getString(_languageKey);
    final controller = OrexL10n._(
      _supports(stored) ? stored! : 'system',
    );
    _instance = controller;
    return controller;
  }

  Future<void> setLanguage(String language) async {
    if (!_supports(language) || language == _language) return;
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, _language);
  }

  /// Returns the entries supplied by this locale, without English fallbacks.
  static Map<String, String> catalogFor(Locale locale) =>
      _catalogs[locale.languageCode]?.translations ?? const {};

  static String tr(String source) =>
      catalogFor(instance.locale)[source] ?? source;

  /// Replaces placeholders in one pass, including when an argument contains {}.
  static String trf(String source, List<Object?> args) {
    var index = 0;
    return tr(source).replaceAllMapped(
      '{}',
      (_) => index < args.length ? '${args[index++]}' : '{}',
    );
  }

  static const _ruMonthsGenitive = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const _enMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// [unit] is the English singular: 'server', 'day', 'hour' or 'minute'.
  String plural(int value, String unit) {
    final currentLocale = locale;
    final translations = catalogFor(currentLocale);
    final one = translations['{} $unit'];
    final other = translations['{} ${unit}s'];
    if (one == null || other == null) {
      return '$value ${value == 1 ? unit : '${unit}s'}';
    }
    final template = Intl.pluralLogic(
      value,
      locale: currentLocale.languageCode,
      useExplicitNumberCases: false,
      zero: translations['{} ${unit}s (zero)'],
      one: one,
      two: translations['{} ${unit}s (two)'],
      few: translations['{} ${unit}s (few)'],
      many: translations['{} ${unit}s (many)'],
      other: other,
    );
    return template.replaceFirst('{}', '$value');
  }

  String dayMonth(DateTime date) => switch (locale.languageCode) {
        'ru' => '${date.day} ${_ruMonthsGenitive[date.month - 1]}',
        'en' => '${_enMonths[date.month - 1]} ${date.day}',
        final language => DateFormat.MMMd(language).format(date),
      };
}

extension OrexL10nString on String {
  String get tr => OrexL10n.tr(this);

  String trf(List<Object?> args) => OrexL10n.trf(this, args);
}
