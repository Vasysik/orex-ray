#!/usr/bin/env python3
"""Drop `const` on lines containing .tr (extension calls are never const),
and report lines for a second manual pass."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"

for path in sorted(ROOT.rglob("*.dart")):
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    changed = False
    out = []
    for line in lines:
        if ".tr" in line and "const " in line:
            new = line.replace("const ", "")
            if new != line:
                changed = True
                line = new
        out.append(line)
    if changed:
        path.write_text("".join(out), encoding="utf-8")
        print(path.relative_to(ROOT))
