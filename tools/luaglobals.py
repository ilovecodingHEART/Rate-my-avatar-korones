#!/usr/bin/env python3
"""List every name a script calls that it never declares.

Anything left over after the known Roblox globals are filtered out is almost
always a typo or a function that got renamed in one place but not the other.
Both read as nil at run time rather than failing at load, so they are worth
catching before the place is opened.
"""
import re
import sys

KNOWN = {
    # Lua
    "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs",
    "loadstring", "next", "pairs", "pcall", "print", "rawequal", "rawget",
    "rawset", "require", "select", "setfenv", "setmetatable", "tonumber",
    "tostring", "type", "unpack", "xpcall", "string", "table", "math", "os",
    "coroutine", "bit32", "utf8", "debug",
    # Roblox
    "game", "workspace", "script", "shared", "Instance", "Enum", "Vector2",
    "Vector3", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "Ray",
    "Region3", "TweenInfo", "NumberRange", "NumberSequence",
    "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint",
    "PhysicalProperties", "Random", "Faces", "Axes", "Rect", "spawn", "delay",
    "wait", "tick", "time", "typeof", "warn", "elapsedTime", "task", "DateTime",
    "settings", "UserSettings", "PluginManager", "version", "Font",
    # loop/scope names that are declared inline rather than with `local`
    "self",
    # keywords, which the "name followed by ( or {" pattern also matches
    "and", "or", "not", "return", "function", "if", "elseif", "while",
    "until", "then", "do", "else", "end", "for", "in", "local", "repeat",
    "break", "nil", "true", "false",
}

DECL_FUNC = re.compile(r"\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)")
DECL_VAR = re.compile(r"\blocal\s+([A-Za-z_][A-Za-z0-9_,\s]*?)(?:\s*=|\s*$)", re.M)
PARAMS = re.compile(r"function\s*(?:[A-Za-z_][A-Za-z0-9_.:]*)?\s*\(([^)]*)\)")
FORLOOP = re.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s+(?:=|in)\b")
USE = re.compile(r"(?<![.:\w])([A-Za-z_][A-Za-z0-9_]*)\s*[({]")


def strip_noise(src):
    src = re.sub(r"--\[\[.*?\]\]", " ", src, flags=re.S)
    src = re.sub(r"--[^\n]*", " ", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\])*'", "''", src)
    return src


def main(path):
    src = strip_noise(open(path, encoding="utf8").read())

    defined = set(KNOWN)
    defined |= set(DECL_FUNC.findall(src))
    for blob in DECL_VAR.findall(src):
        for nm in blob.split(","):
            nm = nm.strip()
            if nm and nm != "function":
                defined.add(nm)
    for blob in PARAMS.findall(src) + FORLOOP.findall(src):
        for nm in blob.split(","):
            nm = nm.strip().lstrip(".")
            if nm:
                defined.add(nm)

    unknown = sorted({n for n in USE.findall(src) if n not in defined})

    if unknown:
        print("%s: %d undeclared name(s) called" % (path, len(unknown)))
        for n in unknown:
            print("   ", n)
    else:
        print("%s: clean" % path)
    return 1 if unknown else 0


if __name__ == "__main__":
    rc = 0
    for p in sys.argv[1:]:
        rc |= main(p)
    sys.exit(rc)
