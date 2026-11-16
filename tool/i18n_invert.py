"""Invert the l10n source language: RU source keys -> EN source keys.

- Parses lib/shared/l10n/orex_l10n_en.dart (RU -> EN).
- Rewrites every literal '<ru>'.tr / '<ru>'.trf( call site in lib/ to the
  English source string.
- Emits lib/shared/l10n/orex_l10n_ru.dart (EN -> RU const map).
- Keys listed in SKIP_KEYS (plural forms, month names) are left untouched;
  their call sites are refactored by hand to locale-aware helpers.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN_MAP = os.path.join(ROOT, 'lib/shared/l10n/orex_l10n_en.dart')
RU_MAP = os.path.join(ROOT, 'lib/shared/l10n/orex_l10n_ru.dart')

# These stay out of the map; handled by OrexL10n.plural()/dayMonth().
SKIP_KEYS = {
    'день', 'дня', 'дней',
    'минута', 'минуты', 'минут',
    'час', 'часа', 'часов',
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
}

# ru key -> EN source to use (overrides map value; used to split/merge).
EN_OVERRIDE = {
    'Системные': 'System apps',
    'Импортировать профиль': 'Import a profile',
}

# EN source -> RU translation to store (overrides inverted key; used when
# several RU strings merge into one EN source and we must pick one form).
RU_OVERRIDE = {
    '{} is too long': '{} слишком длинный',
    'Cancel': 'Отмена',
    'Connection error': 'Ошибка подключения',
    'security={} is not supported yet': 'Пока не поддерживается security={}',
    'transport={} is not supported yet': 'Пока не поддерживается transport={}',
    'Ungroup': 'Расформировать группу',
    'System proxy': 'Системный прокси',
    'Too many ALPN values': 'Слишком много значений ALPN',
    'Export servers as Xray JSON': 'Экспорт серверов JSON Xray',
}

ENTRY = re.compile(
    r"^  '((?:[^'\\]|\\.)*)':\s*\n?\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$", re.M)


def unescape(text):
    return (text.replace('\\\\', '\x00').replace('\\"', '"')
            .replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$')
            .replace('\x00', '\\'))


def escape(text):
    return (text.replace('\\', '\\\\').replace("'", "\\'")
            .replace('\n', '\\n').replace('$', '\\$'))


def main():
    src = io.open(EN_MAP, encoding='utf-8').read()
    pairs = [(unescape(k), unescape(v)) for k, v in ENTRY.findall(src)]
    print('parsed map entries:', len(pairs))

    # Resolve the final EN source for every RU key.
    ru_to_en = {}
    for ru, en in pairs:
        if ru in SKIP_KEYS:
            continue
        ru_to_en[ru] = EN_OVERRIDE.get(ru, en)

    # Build the new EN -> RU map. On merge collisions the first RU spelling
    # wins unless RU_OVERRIDE pins a specific form.
    en_to_ru = {}
    for ru, en in ru_to_en.items():
        en_to_ru.setdefault(en, ru)
    for en, ru in RU_OVERRIDE.items():
        en_to_ru[en] = ru
    # Built-in preset names/descriptions became English in the JSON assets;
    # their RU text rides the same map (shown via preview.name.tr).
    for en, ru in [
        ('Oreshka Gray theme', 'Серая тема Орешка'),
        ('Graphite shades with a copper accent and a squirrel',
         'Графитовые оттенки с медным акцентом и белочкой'),
        ('Classic Orex', 'Классический Orex'),
        ('The original look with copper, ochre and a squirrel',
         'Оригинальное оформление с медью, охрой и белочкой'),
        ('A soft lime theme with a cat and a cabbage',
         'Мягкая салатовая тема с котом и капустой'),
        ('A black and red theme with a squirrel',
         'Чёрно-красная тема с белочкой'),
        ('A black and green theme with a hacker cat',
         'Чёрно-зелёная тема с котом-хакером'),
        # New templates used by the locale-aware plural/date helpers.
        ('Until {} · {}', 'До {} · {}'),
        ('updated {} ago', 'обновлено {} назад'),
    ]:
        en_to_ru[en] = ru

    # Rewrite call sites in lib/ (skip the l10n files themselves).
    dart_files = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, 'lib')):
        for name in files:
            if name.endswith('.dart') and 'l10n' not in dirpath:
                dart_files.append(os.path.join(dirpath, name))
    total_replacements = 0
    for path in dart_files:
        text = io.open(path, encoding='utf-8').read()
        original = text
        for ru, en in ru_to_en.items():
            lit_ru = "'" + ru.replace('\\', '\\\\').replace("'", "\\'") \
                .replace('\n', '\\n').replace('$', '\\$') + "'"
            lit_en = "'" + escape(en) + "'"
            text, n1 = re.subn(re.escape(lit_ru) + r'\.trf\(',
                               lit_en + '.trf(', text)
            text, n2 = re.subn(re.escape(lit_ru) + r'\.tr(?![A-Za-z])',
                               lit_en + '.tr', text)
            total_replacements += n1 + n2
        if text != original:
            io.open(path, 'w', encoding='utf-8', newline='\n').write(text)
    print('call-site replacements:', total_replacements)

    # Report any remaining Russian literal .tr/.trf call sites.
    leftovers = []
    leftover_pat = re.compile(
        r"'([^'\n]*[А-Яа-яЁё][^'\n]*)'\.trf?\b")
    for path in dart_files:
        text = io.open(path, encoding='utf-8').read()
        for m in leftover_pat.finditer(text):
            key = m.group(1)
            if key not in SKIP_KEYS:
                leftovers.append((os.path.relpath(path, ROOT), key[:60]))
    print('leftover RU call sites:', len(leftovers))
    for path, key in leftovers[:20]:
        print('  ', path, '->', key)

    # Emit the RU map.
    lines = [
        '/// Russian translations for the English source strings. Generated by',
        '/// tool/i18n_invert.py from the previous English map; edit by hand.',
        'const orexL10nRu = <String, String>{',
    ]
    for en in sorted(en_to_ru, key=str.lower):
        lines.append("  '%s': '%s'," % (escape(en), escape(en_to_ru[en])))
    lines.append('}')
    lines.append('')
    io.open(RU_MAP, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    print('wrote', RU_MAP, 'entries:', len(en_to_ru))


if __name__ == '__main__':
    sys.exit(main())
