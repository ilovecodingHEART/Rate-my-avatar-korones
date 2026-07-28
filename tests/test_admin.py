"""Admin panel: access control, creating/editing/deleting gamepasses,
persistence, and that a new pass immediately works in the shop."""
import os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, 'src/ServerScriptService/BoothServer.server.lua')
MOCK = os.path.join(ROOT, 'tests/roblox_mock.lua')

UPLOAD, BOOMBOX, PERMANENT = 356360, 353454, 353447

def boot(owned=(), store=None):
    L = LuaRuntime(unpack_returned_tuples=True); g = L.globals()
    M = L.execute(open(MOCK).read()); M.install(g, None)
    L.execute("""
    local M = ...
    local MPS = M.MPS
    MPS.PlayerOwnsAsset = function(a1,a2,a3)
      local plr,id
      if a1==MPS then plr,id=a2,a3 else plr,id=a1,a2 end
      if M.mps.err then error("api down") end
      return M.owned[id] == true
    end
    """, M)
    t = L.eval("{}")
    for i in owned: t[i] = True
    M.owned = t
    if store:
        for k, v in store.items():
            if isinstance(v, dict):
                outer = L.eval("{}")
                for kk, vv in v.items():
                    inner = L.eval("{}")
                    for f, val in vv.items():
                        inner[f] = val
                    outer[kk] = inner
                M.store[k] = outer
            else:
                M.store[k] = v

    new = M.new
    b = new("Model", "Booth", M.booths)
    d = new("Part", "Display", b)
    d.Position = L.eval("({X=0,Y=0,Z=0})")
    sg = new("SurfaceGui", "SurfaceGui", d)
    new("ImageLabel", "ImageLabel", sg); new("TextLabel", "TextLabel", sg)
    at = new("Attachment", "Attachment", d)
    pr = new("ProximityPrompt", "ProximityPrompt", at); pr.Triggered = M.newSignal()
    new("ObjectValue", "BoothOwner", d)
    pn = new("Part", "PartNamePlayer", b)
    s2 = new("SurfaceGui", "SurfaceGui", pn); new("TextLabel", "TextLabel", s2)

    L.execute(open(SERVER).read())
    return L, M, b, pr

def mkplayer(M, name="Nobody", uid=1):
    p = M.new("Player", name, M.Players)
    p.UserId = uid
    M.new("Backpack", "Backpack", p)
    p.CharacterAdded = M.newSignal()
    return p

def msgs(M):
    return [(m.a, m.b) for m in list(M.toClient.values())]

ok = []
def check(l, c, e=""):
    ok.append(c); print(("PASS  " if c else "FAIL  ") + l + (("   " + e) if e else ""))

def tbl(L, d):
    t = L.eval("{}")
    for k, v in d.items(): t[k] = v
    return t

print("=== access control ===")
L, M, b, pr = boot()
admin = mkplayer(M, "Thugshaker", 10)
rando = mkplayer(M, "SomeGuy", 11)
M.Players.PlayerAdded.Fire(admin)
M.Players.PlayerAdded.Fire(rando)

acc = {}
for m in msgs(M):
    if m[0] == "AdminAccess":
        acc.setdefault(len(acc), m[1])
allmsg = msgs(M)
admin_flags = [m[1] for m in allmsg if m[0] == "AdminAccess"]
check("AdminAccess sent on join", len(admin_flags) == 2, str(admin_flags))
check("admin gets true, rando gets false",
      admin_flags[0] is True and admin_flags[1] is False, str(admin_flags))

M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(rando, "AdminOpen")
check("non-admin AdminOpen returns nothing",
      not any(m[0] == "AdminState" for m in msgs(M)))

M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminOpen")
st = [m for m in msgs(M) if m[0] == "AdminState"]
check("admin gets AdminState", len(st) == 1)
entries = list(st[0][1].values()) if st else []
check("lists the 3 builtin passes", len(entries) == 3, str(len(entries)))
check("builtins flagged", all(e.Builtin for e in entries))

print("\n=== non-admin cannot write ===")
M.clock += 100
M.remote.OnServerEvent.Fire(rando, "AdminSavePass",
    tbl(L, {"Key": "HACK", "Title": "Hacked", "Id": 999}))
M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminOpen")
st = [m for m in msgs(M) if m[0] == "AdminState"]
keys = [e.Key for e in st[-1][1].values()]
check("rando's pass was NOT created", "HACK" not in keys, str(keys))

print("\n=== create a pass ===")
M.clock += 100
M.remote.OnServerEvent.Fire(admin, "AdminSavePass", tbl(L, {
    "Key": "speed pass", "Title": "Speed Boost", "Id": 424242,
    "Price": "Gamepass", "Icon": "12345", "Blurb": "Run faster.",
    "Category": "Passes"}))
res = [m for m in msgs(M) if m[0] in ("AdminOk", "AdminError")]
check("save reported ok", res and res[-1][0] == "AdminOk", str(res[-1] if res else None))

M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminOpen")
st = [m for m in msgs(M) if m[0] == "AdminState"]
bykey = {e.Key: e for e in st[-1][1].values()}
check("key normalised to SPEED_PASS", "SPEED_PASS" in bykey, str(list(bykey.keys())))
if "SPEED_PASS" in bykey:
    e = bykey["SPEED_PASS"]
    check("title kept", e.Title == "Speed Boost", e.Title)
    check("icon normalised to rbxassetid://", e.Icon == "rbxassetid://12345", e.Icon)
    check("not marked builtin", e.Builtin is False)

print("\n=== new pass reaches the shop ===")
M.toClient = L.eval("{}")
M.clock += 100
M.remote.OnServerEvent.Fire(admin, "CheckPasses")
ps = [m for m in msgs(M) if m[0] == "PassState"]
shopkeys = [e.Key for e in ps[-1][1].values()] if ps else []
check("shop now lists 4 items", len(shopkeys) == 4, str(shopkeys))
check("SPEED_PASS is in the shop", "SPEED_PASS" in shopkeys)

print("\n=== purchase routing for the new pass ===")
M.clock += 100
M.remote.OnServerEvent.Fire(admin, "PromptPurchase", "SPEED_PASS")
pmt = list(M.mps.prompts.values())
check("prompts the new asset id", pmt and pmt[-1].id == 424242,
      str(pmt[-1].id if pmt else None))
M.owned[424242] = True
M.MPS.PromptPurchaseFinished.Fire(admin, 424242, True)
M.toClient = L.eval("{}")
M.clock += 100
M.remote.OnServerEvent.Fire(admin, "CheckPasses")
ps = [m for m in msgs(M) if m[0] == "PassState"]
owned_now = {e.Key: e.Owns for e in ps[-1][1].values()}
check("buying the new pass marks it Owned", owned_now.get("SPEED_PASS") is True,
      str(owned_now))
check("buying it did not unlock UPLOAD", owned_now.get("UPLOAD") is False)

print("\n=== validation ===")
def try_save(d, label, should_fail=True):
    M.clock += 100
    M.toClient = L.eval("{}")
    M.remote.OnServerEvent.Fire(admin, "AdminSavePass", tbl(L, d))
    got = [m for m in msgs(M) if m[0] in ("AdminOk", "AdminError")]
    failed = bool(got) and got[-1][0] == "AdminError"
    check(label, failed == should_fail, str(got[-1][1] if got else None))

try_save({"Key": "", "Title": "X", "Id": 1}, "empty key rejected")
try_save({"Key": "OK1", "Title": "X", "Id": 0}, "zero id rejected")
try_save({"Key": "OK2", "Title": "  ", "Id": 555}, "blank title rejected")
try_save({"Key": "DUPE", "Title": "Dupe", "Id": UPLOAD}, "duplicate asset id rejected")
try_save({"Key": "FINE", "Title": "Fine", "Id": 777001, "Category": "Passes"},
         "valid pass accepted", should_fail=False)

print("\n=== builtins are protected ===")
M.clock += 100
M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminDeletePass", "UPLOAD")
got = [m for m in msgs(M) if m[0] in ("AdminOk", "AdminError")]
check("cannot delete a builtin", got and got[-1][0] == "AdminError",
      str(got[-1][1] if got else None))

M.clock += 100
M.remote.OnServerEvent.Fire(admin, "AdminSavePass", tbl(L, {
    "Key": "UPLOAD", "Title": "Renamed Upload", "Id": 999999}))
M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminOpen")
st = [m for m in msgs(M) if m[0] == "AdminState"]
up = [e for e in st[-1][1].values() if e.Key == "UPLOAD"][0]
check("builtin title CAN be renamed", up.Title == "Renamed Upload", up.Title)
check("builtin id is NOT changed", up.Id == UPLOAD, str(up.Id))

print("\n=== delete a custom pass ===")
M.clock += 100
M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminDeletePass", "SPEED_PASS")
got = [m for m in msgs(M) if m[0] in ("AdminOk", "AdminError")]
check("delete reported ok", got and got[-1][0] == "AdminOk",
      str(got[-1][1] if got else None))
M.toClient = L.eval("{}")
M.remote.OnServerEvent.Fire(admin, "AdminOpen")
st = [m for m in msgs(M) if m[0] == "AdminState"]
keys = [e.Key for e in st[-1][1].values()]
check("SPEED_PASS gone", "SPEED_PASS" not in keys, str(keys))
check("builtins survive", all(k in keys for k in ("UPLOAD", "PERMANENT", "BOOMBOX")))

print("\n=== persistence across a restart ===")
def lua_to_py(t):
    out = {}
    for k in t:
        v = t[k]
        try:
            out[k] = lua_to_py(v) if hasattr(v, 'values') and not isinstance(v, (str, int, float, bool)) else v
        except Exception:
            out[k] = v
    return out
saved = lua_to_py(M.store)
check("custom passes were written to the datastore", "passes" in saved, str(list(saved.keys())))
L2, M2, b2, pr2 = boot(store=saved)
a2 = mkplayer(M2, "Thugshaker", 10)
M2.Players.PlayerAdded.Fire(a2)
M2.remote.OnServerEvent.Fire(a2, "AdminOpen")
st = [m for m in msgs(M2) if m[0] == "AdminState"]
keys2 = [e.Key for e in st[-1][1].values()]
check("FINE survived the restart", "FINE" in keys2, str(keys2))
check("deleted pass stayed deleted", "SPEED_PASS" not in keys2)
check("builtin rename did NOT persist (code wins)",
      [e for e in st[-1][1].values() if e.Key == "UPLOAD"][0].Title == "Image Upload")

print("\n=== place owner fallback ===")
L3, M3, b3, pr3 = boot()
L3.execute("game.CreatorId = 4242")
owner = mkplayer(M3, "RandomOwner", 4242)
M3.Players.PlayerAdded.Fire(owner)
flags = [m[1] for m in msgs(M3) if m[0] == "AdminAccess"]
check("place owner is admin even if not listed", flags and flags[-1] is True, str(flags))

print()
bad = [x for x in ok if not x]
print("%d/%d checks passed" % (len(ok) - len(bad), len(ok)))
sys.exit(1 if bad else 0)
