"""Load the REAL rateava3.rbxl Workspace into the mock and confirm the server
self-heals it: 18 loose 'boothgood' models become claimable booths."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rbxl_reader import load, nm
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, 'src/ServerScriptService/BoothServer.server.lua')
MOCK = os.path.join(ROOT, 'tests/roblox_mock.lua')
PLACE = os.path.join(ROOT, 'rateava3.rbxl')

I, P = load(PLACE)
ch = {}
for a, b in P.items(): ch.setdefault(b, []).append(a)
wsref = [r for r in ch.get(-1, []) if nm(I, r) == 'Workspace'][0]

L = LuaRuntime(unpack_returned_tuples=True); g = L.globals()
M = L.execute(open(MOCK).read()); M.install(g, None)
L.execute("""
local M = ...
local MPS = M.MPS
MPS.PlayerOwnsAsset = function(a1,a2,a3) return false end
""", M)
M.owned = L.eval("{}")

new = M.new
WS = M.Workspace
# the real place already has an (empty) Booths folder
M.booths.Parent = None

BASE = {'Part','UnionOperation','MeshPart','SpawnLocation'}
def build(ref, parent):
    i = I[ref]
    o = new(i['class'], nm(I, ref), parent)
    pr = i['props']
    if i['class'] == 'ProximityPrompt':
        o.Triggered = M.newSignal()
    if i['class'] in ('Folder','Model'):
        o.ChildAdded = M.newSignal()
    if 'CFrame' in pr:
        (px,py,pz), rot = pr['CFrame']
        o.CFrame = L.eval("({X=%r,Y=%r,Z=%r})" % (px,py,pz))
    for c in ch.get(ref, []): build(c, o)
    return o

for c in ch.get(wsref, []): build(c, WS)

loose = sum(1 for c in ch.get(wsref, []) if nm(I, c) == 'boothgood')
folder = WS.FindFirstChild(WS, "Booths")
before = len(list(folder.GetChildren(folder).values())) if folder else -1
print("rateava3 loaded: %d loose 'boothgood', Booths folder has %d" % (loose, before))

ok = []
def check(l, c, e=""):
    ok.append(c); print(("PASS  " if c else "FAIL  ") + l + (("   " + e) if e else ""))

check("18 loose booths present, folder empty (the real bug)", loose == 18 and before == 0)

L.execute(open(SERVER).read())

folder = WS.FindFirstChild(WS, "Booths")
kids = list(folder.GetChildren(folder).values())
check("server adopted all 18", len(kids) == 18, str(len(kids)))
check("all named 'Booth'", all(k.Name == "Booth" for k in kids),
      str(sorted(set(k.Name for k in kids))))

left = sum(1 for d in WS.GetChildren(WS).values()
           if d.ClassName == "Model" and d.Name == "boothgood")
check("no 'boothgood' left loose in Workspace", left == 0, str(left))

structural = 0
for k in kids:
    d = k.FindFirstChild(k, "Display")
    if d and d.FindFirstChild(d, "BoothOwner") and d.FindFirstChild(d, "SurfaceGui"):
        structural += 1
check("all 18 keep their structure", structural == 18, str(structural))

imgs = set()
for k in kids:
    imgs.add(k.Display.SurfaceGui.ImageLabel.Image)
check("all show the 821176 default", imgs == {"rbxassetid://821176"}, str(imgs))

# claimable?
p = M.new("Player", "Tester", M.Players)
p.UserId = 5
M.new("Backpack", "Backpack", p)
p.CharacterAdded = M.newSignal()
M.Players.PlayerAdded.Fire(p)
b0 = kids[0]
b0.Display.Attachment.ProximityPrompt.Triggered.Fire(p)
owned = p.FindFirstChild(p, "OwnedBooth")
check("booth is CLAIMABLE after self-heal",
      owned is not None and owned.Value is not None)
check("nameplate updated", b0.PartNamePlayer.SurfaceGui.TextLabel.Text == "Tester",
      str(b0.PartNamePlayer.SurfaceGui.TextLabel.Text))

print()
bad = [x for x in ok if not x]
print("%d/%d checks passed" % (len(ok) - len(bad), len(ok)))
sys.exit(1 if bad else 0)
