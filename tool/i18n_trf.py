#!/usr/bin/env python3
"""Convert interpolated Russian string literals to .trf templates.

'Импортируем $name…'           -> 'Импортируем {}…'.trf([name])
'HTTP ${r.statusCode} для $f'  -> 'HTTP {} для {}'.trf([r.statusCode, f])
Only touches literals without an existing .tr/.trf suffix.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
CYR = re.compile(r"[А-Яа-яЁё]")
LIT = re.compile(r"'(?:[^'\\]|\\.)*'")


def convert(literal: str):
    inner = literal[1:-1]
    if "$" not in inner or not CYR.search(inner):
        return None
    out = []
    args = []
    i = 0
    n = len(inner)
    while i < n:
        c = inner[i]
        if c == "\\":
            out.append(inner[i:i + 2])
            i += 2
            continue
        if c == "$":
            if i + 1 < n and inner[i + 1] == "{":
                depth = 1
                j = i + 2
                while j < n and depth:
                    if inner[j] == "{":
                        depth += 1
                    elif inner[j] == "}":
                        depth -= 1
                    j += 1
                if depth:
                    return None
                args.append(inner[i + 2:j - 1])
                out.append("{}")
                i = j
                continue
            m = re.match(r"[A-Za-z_]\w*", inner[i + 1:])
            if m:
                args.append(m.group(0))
                out.append("{}")
                i += 1 + len(m.group(0))
                continue
            return None
        out.append(c)
        i += 1
    if not args:
        return None
    template = "".join(out)
    return f"'{template}'.trf([{', '.join(args)}])"


changed_files = 0
for path in sorted(ROOT.rglob("*.dart")):
    if "l10n" in path.parts:
        continue
    lines = path.read_text(encoding="utf-8").read_text if False else None
    text = path.read_text(encoding="utf-8")
    original = text
    pieces = []
    pos = 0
    for m in LIT.finditer(text):
        literal = m.group(0)
        tail = text[m.end():m.end() + 4]
        new = None
        if not tail.startswith(".tr"):
            new = convert(literal)
        if new:
            pieces.append(text[pos:m.start()])
            pieces.append(new)
            pos = m.end()
    if pos:
        pieces.append(text[pos:])
        path.write_text("".join(pieces), encoding="utf-8")
        changed_files += 1
        print(path.relative_to(ROOT))

print(f"\n{changed_files} files updated")
