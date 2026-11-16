#!/usr/bin/env python3
"""Inventory Russian string literals per Dart file for the i18n pass."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
CYR = re.compile(r"[А-Яа-яЁё]")
# single or double quoted string literals (naive, no triple-quoted support)
LIT = re.compile(r"""(?<!\\)'((?:[^'\\]|\\.)*)'|(?<!\\)"((?:[^"\\]|\\.)*)\"""")

total = 0
for path in sorted(ROOT.rglob("*.dart")):
    if "l10n" in path.parts:
        continue
    text = path.read_text(encoding="utf-8")
    strings = []
    for i, line in enumerate(text.splitlines(), 1):
        # skip comment-only lines
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        for m in LIT.finditer(line):
            value = m.group(1) if m.group(1) is not None else m.group(2)
            if CYR.search(value):
                strings.append((i, value))
    if strings:
        rel = path.relative_to(ROOT)
        print(f"\n== {rel} ({len(strings)})")
        for line, value in strings:
            print(f"  {line}: {value}")
        total += len(strings)
print(f"\nTOTAL: {total}")
