#!/usr/bin/env bash
#
# Check the scripts, run the tests, then write them back into the place file.
#
# Nothing is packed unless everything passes, so the .rbxl in the repo is
# always a build that got through the suite.

set -euo pipefail

cd "$(dirname "$0")/.."

# The current place. rateav33.rbxl supersedes latestratemyavatar.rbxl and
# carries the AFK scripts, which this build leaves untouched.
PLACE="rateav33.rbxl"

echo "== syntax"
python3 tools/luacheck.py src/*.lua

echo
echo "== ordering"
python3 tools/luaorder.py src/Server.server.lua src/Client.client.lua

echo
echo "== undeclared names"
python3 tools/luaglobals.py src/Server.server.lua src/Client.client.lua

echo
echo "== layout"
python3 tools/checklayout.py src/Client.client.lua -q

echo
echo "== tests"
python3 tools/runtests.py | tail -5

echo
echo "== packing $PLACE"
python3 tools/rbxl_edit.py "$PLACE" src "$PLACE.new"
mv "$PLACE.new" "$PLACE"

echo
echo "== verifying what landed in the place"
python3 - <<'PY'
import sys
sys.path.insert(0, "tools")
from rbxl_parse import parse, path_of

WANT = {
    "ServerScriptService/Server": "src/Server.server.lua",
    "StarterGui/MainUI/Client": "src/Client.client.lua",
}

inst, parents, _ = parse("rateav33.rbxl")
seen = 0
for ref, node in inst.items():
    src = node["props"].get("Source")
    if not src:
        continue
    p = path_of(inst, parents, ref)
    if p in WANT:
        disk = open(WANT[p], "rb").read()
        assert src == disk, "%s does not match %s" % (p, WANT[p])
        seen += 1

assert seen == len(WANT), "expected %d scripts in the place, found %d" % (len(WANT), seen)
print("   both scripts in the place match src/ exactly")
PY

echo
echo "done"
