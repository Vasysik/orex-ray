#!/usr/bin/env python3
"""Merge adjacent string literals that the i18n wrap split apart:
   'aaa'.tr
   'bbb'
becomes 'aaabbb'.tr. Interpolated parts ($) are reported for manual work."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
LIT = r"'(?:[^'\\]|\\.)*'"
# literal with .tr, newline + indent, another literal starting the line
PAT = re.compile(
    rf"(?P<a>{LIT})\.tr(?P<ws>\n[ \t]*)(?P<b>{LIT})",
)
PAT2 = re.compile(
    rf"(?P<a>{LIT})\.tr(?P<ws>\n[ \t]*)(?P<b>{LIT})\.tr",
)

for path in sorted(ROOT.rglob("*.dart")):
    text = path.read_text(encoding="utf-8")
    original = text
    skipped = []

    def merge(m: re.Match) -> str:
        a, b = m.group("a")[1:-1], m.group("b")[1:-1]
        if "$" in a or "$" in b:
            skipped.append((a, b))
            return m.group(0)
        return f"'{a}{b}'.tr"

    prev = None
    while prev != text:
        prev = text
        text = PAT2.sub(merge, text)
        text = PAT.sub(merge, text)

    if text != original:
        path.write_text(text, encoding="utf-8")
    if skipped:
        rel = path.relative_to(ROOT)
        print(f"{rel}: {len(skipped)} interpolated concatenation(s) left")
