#!/usr/bin/env python3
"""Syntax-check Lua sources with the bundled Lua 5.1 parser.

Luau is a superset of 5.1's grammar for everything these scripts use, so a
clean 5.1 parse means Studio will load the script. The 5.1 parser also enforces
the limits that actually bite in a long single-file script - 200 locals per
function and 60 upvalues per closure - so a pass here means the real limits are
respected too.
"""
import sys

from lupa import lua51

CHECK = """
function(src, name)
    local fn, err = loadstring(src, name)
    if fn then return true, "" end
    return false, tostring(err)
end
"""


# Lua caps a function at 200 locals, and these are single-file scripts, so the
# whole script body is one function. Running out is a hard compile error rather
# than a warning, so the remaining headroom is measured and a thin margin is
# called out before it becomes a failure.
MIN_HEADROOM = 5


def headroom(check, src, name, cap=60):
    fits = 0
    for n in range(1, cap + 1):
        pad = "\n".join("local __headroom%d = %d" % (i, i) for i in range(n))
        ok, _ = check(src + "\n" + pad, "@" + name)
        if not ok:
            break
        fits = n
    return fits


def main(paths):
    rt = lua51.LuaRuntime()
    check = rt.eval(CHECK)

    bad = 0
    for p in paths:
        src = open(p, encoding="utf8").read()
        ok, err = check(src, "@" + p)
        lines = src.count("\n") + 1

        if not ok:
            bad = 1
            print("FAIL  %s\n      %s" % (p, err))
            continue

        room = headroom(check, src, p)
        note = "%d locals spare" % room
        if room < MIN_HEADROOM:
            bad = 1
            note = "ONLY %d locals spare, the 200 limit is close" % room

        print("OK    %-28s %5d lines   %s" % (p, lines, note))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
