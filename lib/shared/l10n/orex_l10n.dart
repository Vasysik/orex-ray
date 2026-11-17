import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'orex_l10n_ru.dart';

/// Lightweight runtime localization.
///
/// Keys are the English source strings themselves, so call sites stay
/// readable (`'Home'.tr`) and code without a BuildContext (controllers,
/// validators) translates the same way. Missing Russian entries fall back to
/// the English source, which keeps partial translations shippable.
class OrexL10n extends ChangeNotifier {
  OrexL10n._(this._language);

  static const _languageKey = 'orex_ray_language';

  /// 'system', 'ru' or 'en'.
  static const supportedLanguages = <String>['system', 'ru', 'en'];

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  static OrexL10n? _instance;

  /// Null before [load] completes; the launch splash must tolerate that.
  static OrexL10n? get instanceOrNull => _instance;

  /// Loaded once by the bootstrap before the first frame. Tests never call
  /// [load]; they transparently get a Russian default so localized widgets
  /// keep their source-language assertions.
  static OrexL10n get instance => _instance ??= OrexL10n._('ru');

  String _language;
  String get language => _language;

  /// English is the international fallback: only Russian systems get Russian.
  Locale get locale {
    final effective = _language == 'system'
        ? (Platform.localeName.toLowerCase().startsWith('ru') ? 'ru' : 'en')
        : _language;
    return Locale(effective);
  }

  bool get isRussian => locale.languageCode == 'ru';

  static Future<OrexL10n> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_languageKey);
    final controller = OrexL10n._(
      supportedLanguages.contains(stored) ? stored! : 'system',
    );
    _instance = controller;
    return controller;
  }

  Future<void> setLanguage(String language) async {
    if (!supportedLanguages.contains(language) || language == _language) {
      return;
    }
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language);
  }

  /// Translates an English source string into the active language.
  static String tr(String source) {
    final l10n = _instance ??= OrexL10n._('ru');
    if (!l10n.isRussian) return source;
    return orexL10nRu[source] ?? source;
  }

  /// Translates a template and substitutes `{}` placeholders in order.
  static String trf(String source, List<Object?> args) {
    var result = tr(source);
    for (final arg in args) {
      result = result.replaceFirst('{}', '$arg');
    }
    return result;
  }

  /// Russian plural forms (one / few / many) for the units the UI counts.
  static const _ruPlurals = <String, (String, String, String)>{
    'day': ('день', 'дня', 'дней'),
    'hour': ('час', 'часа', 'часов'),
    'minute': ('минута', 'минуты', 'минут'),
  };

  static const _ruMonthsGenitive = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  static const _enMonths = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// '$value day(s)' with the plural rules of the active language.
  /// [unit] is the English singular: 'day', 'hour' or 'minute'.
  String plural(int value, String unit) {
    if (!isRussian) {
      return '$value ${value == 1 ? unit : '${unit}s'}';
    }
    final forms = _ruPlurals[unit];
    if (forms == null) return '$value $unit';
    final mod100 = value % 100;
    final mod10 = value % 10;
    final form = mod100 >= 11 && mod100 <= 14
        ? forms.$3
        : mod10 == 1
            ? forms.$1
            : mod10 >= 2 && mod10 <= 4
                ? forms.$2
                : forms.$3;
    return '$value $form';
  }

  /// '3 May' / '3 мая' — a day+month date in the active language.
  String dayMonth(DateTime date) => isRussian
      ? '${date.day} ${_ruMonthsGenitive[date.month - 1]}'
      : '${_enMonths[date.month - 1]} ${date.day}';
}

extension OrexL10nString on String {
  /// Translates this English source string via [OrexL10n.tr].
  String get tr => OrexL10n.tr(this);

  /// Translates this template and substitutes `{}` placeholders in order.
  String trf(List<Object?> args) => OrexL10n.trf(this, args);
}
