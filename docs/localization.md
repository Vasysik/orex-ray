# Contributing translations

Open **Interface → Language** to switch languages. Each file in [lib/shared/l10n](../lib/shared/l10n/) supplies a partial catalog. English source strings are the lookup keys and the fallback.

## Translate a screen

1. Find the English source next to `.tr` or `.trf(...)` in the Dart code. Android VPN progress messages used by Flutter also have English sources in the Android service and activity.
2. Add the exact key and its translation to `orex_l10n_<language>.dart`. Copy punctuation and spacing in the key. For each `{}` in the source, keep one `{}` in the translation. The arguments are inserted in order.
3. Run `flutter test --no-pub test/orex_l10n_test.dart`. CI checks that supplied entries are nonempty and preserve placeholders. You can translate one screen or one string per PR. Missing entries use English immediately.

```dart
'Checking the route…': 'Sprawdzanie trasy…',
'Copy {}': 'Kopiuj {}',
```

For counted units, use `'{} day'` and `'{} days'` for the singular and common plural. Add locale-specific forms such as `'{} days (few)'` where needed. Supported cases are `zero`, `one` (the singular key), `two`, `few`, `many` and `other` (the plain plural key). The app uses English for the whole quantity if either base entry is missing. Use complete translated phrases for each supplied form.

## Add a language

1. Create a partial catalog alongside the existing catalogs and register its locale, native display name and catalog in [OrexL10n](../lib/shared/l10n/orex_l10n.dart). The picker, system locale resolution and catalog test use that registry.
2. Check startup, profile import, connect, route status and disconnect on a narrow screen. For a right-to-left language, check navigation, dialogs and mixed text such as host names and proxy links.

The Flutter build reads these catalogs directly. The Python scripts in `tool/i18n_*.py` were used during the original migration. Catalog editing and CI require no generation step. Android system notifications and raw native error text are outside these catalogs.
