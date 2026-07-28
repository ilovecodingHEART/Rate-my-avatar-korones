#!/usr/bin/env python3
"""Run the Lua test suite against the booth scripts.

Uses the Lua 5.1 interpreter bundled with lupa, which is the closest available
match to the Luau these scripts target.
"""
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.TOOLS = HERE
    g.SRC = os.path.join(ROOT, "src")
    g.TESTS = os.path.join(ROOT, "tests")

    test_file = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tests", "all.lua")

    ok = rt.execute('return dofile("%s")' % test_file.replace("\\", "/"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
