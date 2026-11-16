#!/usr/bin/env python3
"""Remove `const` from constructor/collection expressions that contain .tr.

Scans each Dart file, finds `const` followed by an identifier + paren or a
collection bracket, matches brackets while skipping strings/comments, and
drops the const keyword when the expression body contains `.tr`.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"


def strip_strings_comments(text: str) -> str:
    """Replace string/comment content with spaces, preserving newlines."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif c in "'\"":
            quote = c
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
        else:
            i += 1
    return "".join(out)


def match_bracket(masked: str, start: int) -> int:
    """Index one past the bracket that closes the one opened at start."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    close = pairs[masked[start]]
    depth = 0
    for i in range(start, len(masked)):
        ch = masked[i]
        if ch == masked[start]:
            depth += 1
        elif ch == close:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(masked)


for path in sorted(ROOT.rglob("*.dart")):
    text = path.read_text(encoding="utf-8")
    masked = strip_strings_comments(text)
    drops = []  # positions of `const` keywords to remove
    i = 0
    while True:
        i = masked.find("const ", i)
        if i < 0:
            break
        j = i + 6
        # skip whitespace
        while j < len(masked) and masked[j] in " \t":
            j += 1
        start = j
        # identifier (with generics) then bracket, or direct bracket
        while j < len(masked) and (masked[j].isalnum() or masked[j] in "_<>,? "):
            if masked[j] in "([{":
                break
            if masked[j] == "\n":
                break
            j += 1
        # find the opening bracket
        while j < len(masked) and masked[j] in " \t":
            j += 1
        if j < len(masked) and masked[j] in "([{":
            end = match_bracket(masked, j)
            if ".tr" in text[j:end] or ".trf" in text[j:end]:
                drops.append(i)
            i = end
        else:
            i = start + 1
    if drops:
        chars = list(text)
        for pos in drops:
            for k in range(pos, pos + 6):
                chars[k] = ""
        path.write_text("".join(chars), encoding="utf-8")
        print(f"{path.relative_to(ROOT)}: dropped {len(drops)} const")
