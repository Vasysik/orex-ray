import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'orex_l10n_en.dart';

/// Lightweight runtime localization.
///
/// Keys are the Russian source strings themselves, so call sites stay
/// readable (`'Главная'.tr`) and code without a BuildContext (controllers,
/// validators) translates the same way. Missing English entries fall back to
/// the Russian source, which keeps partial translations shippable.
class OrexL10n extends ChangeNotifier {
  OrexL10n._(this._language);

  static const _languageKey = 'orex_ray_language';

  /// 'system', 'ru' or 'en'.
  static const supportedLanguages = <String>['system', 'ru', 'en'];

  static const supportedLocales = <Locale>[
    Locale('ru'),
    Locale('en'),
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

  Locale get locale {
    final effective = _language == 'system'
        ? (Platform.localeName.toLowerCase().startsWith('en') ? 'en' : 'ru')
        : _language;
    return Locale(effective);
  }

  bool get isEnglish => locale.languageCode == 'en';

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

  /// Translates a Russian source string into the active language.
  static String tr(String source) {
    final l10n = _instance;
    if (l10n == null || !l10n.isEnglish) return source;
    return orexL10nEn[source] ?? source;
  }

  /// Translates a template and substitutes `{}` placeholders in order.
  static String trf(String source, List<Object?> args) {
    var result = tr(source);
    for (final arg in args) {
      result = result.replaceFirst('{}', '$arg');
    }
    return result;
  }
}

extension OrexL10nString on String {
  /// Translates this Russian source string via [OrexL10n.tr].
  String get tr => OrexL10n.tr(this);

  /// Translates this template and substitutes `{}` placeholders in order.
  String trf(List<Object?> args) => OrexL10n.trf(this, args);
}
