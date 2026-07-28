#!/usr/bin/env python3
"""Catch use-before-definition of file-level locals.

Lua resolves a local only from its declaration onwards, so calling a
`local function` that is declared further down the file silently reads a nil
global instead of erroring at load time. In a 3000 line script that is very
easy to do and very annoying to find at run time, so it gets checked here.
"""
import re
import sys

DECL = re.compile(r"^local (?:function )?([A-Za-z_][A-Za-z0-9_]*)")
# `local a, b = ...`
DECL_MULTI = re.compile(r"^local ([A-Za-z_][A-Za-z0-9_, ]*?)\s*=")
CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*[({\"']")
# `Thing.Field = x` and `Thing:Method()` also read the local, and inside a
# closure they are not called until later - so the parser sees no error but the
# name is still nil at run time if it is declared further down. A UIScale fix
# shipped with exactly this shape and only the test suite caught it.
TOUCH = re.compile(r"(?<![.:\w])([A-Za-z_][A-Za-z0-9_]*)\s*[.:][A-Za-z_]")


def blank_noise(line):
    """Blank out string literals so text inside them is not read as code."""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(?:\\.|[^'\\])*'", "''", line)
    return line.split("--")[0]


def strip_block_comments(text):
    """Blank out --[[ ]] blocks, keeping line numbers intact.

    The file headers are block comments full of example code, and reading them
    as real statements produced a page of false positives.
    """
    out = []
    depth = 0
    for line in text.split("\n"):
        stripped = line.strip()
        if depth == 0 and stripped.startswith("--[["):
            depth = 1
            out.append("")
            if "]]" in stripped[4:]:
                depth = 0
            continue
        if depth:
            out.append("")
            if "]]" in line:
                depth = 0
            continue
        out.append(line)
    return out


def main(path):
    lines = strip_block_comments(open(path, encoding="utf8").read())

    declared = {}
    for i, line in enumerate(lines):
        if not line.startswith("local "):
            continue
        m = DECL_MULTI.match(line)
        if m and "function" not in m.group(1):
            for nm in m.group(1).split(","):
                nm = nm.strip()
                if nm and nm not in declared:
                    declared[nm] = i
            continue
        m = DECL.match(line)
        if m and m.group(1) not in declared:
            declared[m.group(1)] = i

    problems = []
    for i, line in enumerate(lines):
        code = blank_noise(line)
        for name in list(CALL.findall(code)) + list(TOUCH.findall(code)):
            at = declared.get(name)
            if at is not None and at > i:
                problems.append((i + 1, name, at + 1))

    for lineno, name, declat in problems:
        print("line %d: uses %s, declared at line %d" % (lineno, name, declat))

    print("%s: %d forward reference(s)" % (path, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    rc = 0
    for p in sys.argv[1:]:
        rc |= main(p)
    sys.exit(rc)
