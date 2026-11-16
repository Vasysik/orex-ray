"""Parse the EN map and report duplicate values + total pairs."""
import io
import re
import collections

src = io.open('lib/shared/l10n/orex_l10n_en.dart', encoding='utf-8').read()

# Entries look like:  'key': 'value',  (value may wrap onto the next line)
pat = re.compile(
    r"^  '((?:[^'\\]|\\.)*)':\s*\n?\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$", re.M)

pairs = pat.findall(src)
print('parsed pairs:', len(pairs))

vals = collections.Counter(v for _, v in pairs)
dups = {v: c for v, c in vals.items() if c > 1}
print('duplicate EN values:', len(dups))
for v, c in dups.items():
    keys = [k for k, vv in pairs if vv == v]
    print(c, repr(v[:70]), '<-', [k[:40] for k in keys])
