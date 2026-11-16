#!/usr/bin/env python3
"""Collect all .tr/.trf keys from lib into a sorted unique list."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
LIT = re.compile(r"'((?:[^'\\]|\\.)*)'\.trf?\b")

keys = set()
for path in sorted(ROOT.rglob("*.dart")):
    if "l10n" in path.parts:
        continue
    for m in LIT.finditer(path.read_text(encoding="utf-8")):
        keys.add(m.group(1))

out = sorted(keys)
print(len(out))
Path(__file__).resolve().parent.parent / "tool" / "i18n_keys.txt"
with open("tool/i18n_keys.txt", "w", encoding="utf-8") as fh:
    for key in out:
        fh.write(key + "\n")
