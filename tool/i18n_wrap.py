#!/usr/bin/env python3
"""Wrap plain Russian string literals in `.tr` for the OrexRay i18n pass.

- Skips comments, imports, interpolations (collected for manual trf work),
  and literals already translated.
- Adds the orex_l10n import to every touched file.
- Prints a manual-work list for interpolated strings at the end.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
CYR = re.compile(r"[А-Яа-яЁё]")
LIT = re.compile(r"""('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""")
L10N_PARTS = ("shared", "l10n")

manual = []   # (file, line, literal) interpolated strings
wrapped = {}  # file -> count

def needs_skip_line(stripped: str) -> bool:
    return (
        stripped.startswith("//")
        or stripped.startswith("import ")
        or stripped.startswith("export ")
        or stripped.startswith("part ")
        or stripped.startswith("///")
        or stripped.startswith("* ")
    )

for path in sorted(ROOT.rglob("*.dart")):
    rel = path.relative_to(ROOT)
    if rel.parts[:2] == L10N_PARTS:
        continue
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out = []
    count = 0
    in_block_comment = False
    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if "/*" in line:
            in_block_comment = True
        if in_block_comment:
            out.append(line)
            if "*/" in line:
                in_block_comment = False
            continue
        if needs_skip_line(stripped):
            out.append(line)
            continue

        def repl(m: re.Match) -> str:
            nonlocal count
            literal = m.group(1)
            inner = literal[1:-1]
            if not CYR.search(inner):
                return literal
            tail = line[m.end():m.end() + 4]
            if tail.startswith(".tr"):
                return literal
            if "$" in inner:
                manual.append((str(rel), lineno, literal))
                return literal
            count += 1
            return literal + ".tr"

        new_line = LIT.sub(repl, line)
        out.append(new_line)

    if count:
        text = "".join(out)
        # insert import after the last existing import
        depth = len(rel.parts) - 1
        prefix = "../" * depth
        imp = f"import '{prefix}shared/l10n/orex_l10n.dart';\n"
        if "shared/l10n/orex_l10n.dart" not in text:
            idx = text.rfind("import ")
            end = text.find("\n", idx) + 1
            text = text[:end] + imp + text[end:]
        path.write_text(text, encoding="utf-8")
        wrapped[str(rel)] = count

print("WRAPPED:")
for f, c in wrapped.items():
    print(f"  {f}: {c}")
print(f"\nMANUAL (interpolated): {len(manual)}")
for f, line, lit in manual:
    print(f"  {f}:{line}: {lit}")
