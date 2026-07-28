"""Run the real BoothServer against a Roblox mock: passes, permanent images,
boombox grants, and the ResetBooth-must-not-wipe rule."""
import os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, 'src/ServerScriptService/BoothServer.server.lua')
MOCK = os.path.join(ROOT, 'tests/roblox_mock.lua')

UPLOAD, BOOMBOX, PERMANENT = 356360, 353454, 353447

def boot(owned=(), n_booths=2, store=None):
    L = LuaRuntime(unpack_returned_tuples=True); g = L.globals()
    M = L.execute(open(MOCK).read()); M.install(g, None)
    M.mps.owns = False
    owned_set = set(owned)

    # per-asset ownership
    L.execute("""
    local M = ...
    local MPS = M.MPS
    MPS.PlayerOwnsAsset = function(a1,a2,a3)
      local plr,id
      if a1==MPS then plr,id=a2,a3 else plr,id=a1,a2 end
      table.insert(M.mps.calls, {api="PlayerOwnsAsset", id=id})
      if M.mps.err then error("api down") end
      return M.owned[id] == true
    end
    """, M)
    tbl = L.eval("{}")
    for i in owned_set: tbl[i] = True
    M.owned = tbl

    if store:
        for k,v in store.items(): M.store[k]=v

    new = M.new
    booths = M.booths
    made = []
    for i in range(n_booths):
        b = new("Model","Booth",booths)
        d = new("Part","Display",b)
        d.Position = L.eval("({X=%d,Y=0,Z=0})" % (i*10))
        sg = new("SurfaceGui","SurfaceGui",d)
        new("ImageLabel","ImageLabel",sg); new("TextLabel","TextLabel",sg)
        at = new("Attachment","Attachment",d)
        pr = new("ProximityPrompt","ProximityPrompt",at); pr.Triggered = M.newSignal()
        new("ObjectValue","BoothOwner",d)
        pn = new("Part","PartNamePlayer",b)
        s2 = new("SurfaceGui","SurfaceGui",pn); new("TextLabel","TextLabel",s2)
        made.append((b,pr))
    L.execute(open(SERVER).read())
    return L,M,made

def mkplayer(M, name="P", uid=1):
    p = M.new("Player", name, M.Players)
    p.UserId = uid
    M.new("Backpack","Backpack",p)
    p.CharacterAdded = M.newSignal()
    return p

ok=[]
def check(l,c,e=""):
    ok.append(c); print(("PASS  " if c else "FAIL  ")+l+(("   "+e) if e else ""))

def msgs(M):
    return [(m.a, m.b) for m in list(M.toClient.values())]

print("=== default image ===")
L,M,bs = boot()
b,pr = bs[0]
check("unclaimed booth uses 821176",
      b.Display.SurfaceGui.ImageLabel.Image == "rbxassetid://821176",
      str(b.Display.SurfaceGui.ImageLabel.Image))

print("\n=== no passes ===")
L,M,bs = boot(owned=())
b,pr = bs[0]
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
st=[m for m in msgs(M) if m[0]=="PassState"]
check("join pushes PassState", len(st)==1)
entries={e.Key:e.Owns for e in st[0][1].values()} if st else {}
check("all three passes reported", set(entries.keys())=={"UPLOAD","BOOMBOX","PERMANENT"}, str(entries))
check("none owned", not any(entries.values()), str(entries))
pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","999")
check("no UPLOAD -> image refused",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176",
      str(b.Display.SurfaceGui.ImageLabel.Image))
check("error mentions Gamepass, not a shirt name",
      any(m[0]=="ImageError" and "Gamepass" in str(m[1]) and "hugshaker" not in str(m[1])
          for m in msgs(M)))

print("\n=== UPLOAD only (temporary image) ===")
L,M,bs = boot(owned=(UPLOAD,))
b,pr = bs[0]
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","4242")
check("UPLOAD -> image applies",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://4242")
check("not saved to datastore (no PERMANENT)", len(dict(M.store).keys())==0, str(dict(M.store)))
M.clock+=100
M.remote.OnServerEvent.Fire(p,"UnclaimBooth")
check("unclaim reverts to default when not permanent",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176",
      str(b.Display.SurfaceGui.ImageLabel.Image))

print("\n=== UPLOAD + PERMANENT ===")
L,M,bs = boot(owned=(UPLOAD,PERMANENT))
b,pr = bs[0]
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","777")
check("permanent image applies", b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://777")
check("saved to datastore", "rbxassetid://777" in list(dict(M.store).values()), str(dict(M.store)))
M.clock+=100
M.remote.OnServerEvent.Fire(p,"UnclaimBooth")
check("UNCLAIM DOES NOT WIPE the paid image",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://777",
      str(b.Display.SurfaceGui.ImageLabel.Image))
M.Players.PlayerRemoving.Fire(p)
check("disconnect does not wipe it either",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://777")

print("\n=== inheritance ===")
p2 = mkplayer(M,"Second",2); M.Players.PlayerAdded.Fire(p2)
pr.Triggered.Fire(p2)
check("next claimer inherits the paid image",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://777")

L,M,bs = boot(owned=(), store={"booth_1":"rbxassetid://555"})
b,pr = bs[0]
check("saved image loads on server start",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://555",
      str(b.Display.SurfaceGui.ImageLabel.Image))
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","1")
check("player without UPLOAD is stuck with the inherited image",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://555")

print("\n=== per-item cache isolation ===")
L,M,bs = boot(owned=(BOOMBOX,))
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
b,pr = bs[0]; pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","3")
check("owning BOOMBOX does not unlock UPLOAD",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176")

print("\n=== purchase routing ===")
L,M,bs = boot(owned=())
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
M.clock+=100
M.remote.OnServerEvent.Fire(p,"PromptPurchase","PERMANENT")
pmt=list(M.mps.prompts.values())
check("prompts the right asset id", pmt and pmt[-1].id==PERMANENT, str(pmt[-1].id if pmt else None))
check("uses asset PromptPurchase", pmt and pmt[-1].api=="PromptPurchase")
# buying BOOMBOX must not unlock UPLOAD
M.owned[BOOMBOX]=True
M.MPS.PromptPurchaseFinished.Fire(p, BOOMBOX, True)
st=[m for m in msgs(M) if m[0]=="PassState"]
last={e.Key:e.Owns for e in st[-1][1].values()}
check("after buying BOOMBOX only it flips", last["BOOMBOX"] and not last["UPLOAD"] and not last["PERMANENT"], str(last))
b,pr=bs[0]; pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","8")
check("BOOMBOX purchase did not unlock uploads",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176")

print("\n=== unrelated / cancelled ===")
L,M,bs = boot(owned=())
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
b,pr=bs[0]; pr.Triggered.Fire(p)
M.MPS.PromptPurchaseFinished.Fire(p, 111111, True)
M.MPS.PromptPurchaseFinished.Fire(p, UPLOAD, False)
M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","9")
check("unrelated + cancelled purchases do not unlock",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176")

print("\n=== api failure fails closed ===")
L,M,bs = boot(owned=(UPLOAD,PERMANENT))
M.mps.err = True
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
b,pr=bs[0]; pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","6")
check("ownership API error denies the perk",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://821176")

print("\n=== datastore failure is survivable ===")
L,M,bs = boot(owned=(UPLOAD,PERMANENT))
M.storeFail = True
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
b,pr=bs[0]; pr.Triggered.Fire(p); M.clock+=100
M.remote.OnServerEvent.Fire(p,"ChangeImage","31")
check("image still shows when datastore is down",
      b.Display.SurfaceGui.ImageLabel.Image=="rbxassetid://31")

print("\n=== boombox ===")
L,M,bs = boot(owned=(BOOMBOX,))
tool = M.new("Tool","Boombox",M.ServerStorage)
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
bp = p.Backpack
check("boombox granted to owner", bp.FindFirstChild(bp, "Boombox") is not None)
L,M,bs = boot(owned=())
tool = M.new("Tool","Boombox",M.ServerStorage)
p = mkplayer(M); M.Players.PlayerAdded.Fire(p)
bp = p.Backpack
check("boombox NOT granted to non-owner", bp.FindFirstChild(bp, "Boombox") is None)

print("\n=== booth ownership still enforced ===")
L,M,bs = boot(owned=(UPLOAD,PERMANENT), n_booths=2)
a,pra = bs[0]; c,prc = bs[1]
p1=mkplayer(M,"A",1); p2=mkplayer(M,"B",2)
M.Players.PlayerAdded.Fire(p1); M.Players.PlayerAdded.Fire(p2)
pra.Triggered.Fire(p1)
prc.Triggered.Fire(p1)
check("one booth per player", c.Display.BoothOwner.Value is None)
M.clock+=100
M.remote.OnServerEvent.Fire(p2,"ChangeImage","12")
check("non-owner cannot edit", a.Display.SurfaceGui.ImageLabel.Image!="rbxassetid://12")

print("\n=== self healing: loose booths (the rateava3 bug) ===")
# Build booths NOT in the folder, named "boothgood", like the real place file.
from lupa import LuaRuntime as _LR
L=_LR(unpack_returned_tuples=True); g=L.globals()
M=L.execute(open(MOCK).read()); M.install(g,None)
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
M.owned = L.eval("{}")
new=M.new
WS=M.booths.Parent
prompts=[]
for i in range(18):
    b=new("Model","boothgood",WS)          # loose in Workspace, wrong name
    d=new("Part","Display",b)
    d.Position=L.eval("({X=%d,Y=0,Z=0})"%(i*10))
    sg=new("SurfaceGui","SurfaceGui",d)
    new("ImageLabel","ImageLabel",sg); new("TextLabel","TextLabel",sg)
    at=new("Attachment","Attachment",d)
    pr=new("ProximityPrompt","ProximityPrompt",at); pr.Triggered=M.newSignal()
    new("ObjectValue","BoothOwner",d)
    pn=new("Part","PartNamePlayer",b)
    s2=new("SurfaceGui","SurfaceGui",pn); new("TextLabel","TextLabel",s2)
    prompts.append(pr)
# a decoy that must NOT be adopted
decoy=new("Model","NotABooth",WS); new("Part","Display",decoy)
before=len(list(M.booths.GetChildren(M.booths).values()))
L.execute(open(SERVER).read())
after=list(M.booths.GetChildren(M.booths).values())
check("starts with 0 in the folder", before==0, str(before))
check("server adopts all 18 loose booths", len(after)==18, str(len(after)))
check("all renamed to 'Booth'", all(b.Name=="Booth" for b in after),
      str(sorted(set(b.Name for b in after))))
check("decoy model NOT adopted", decoy.Parent!=M.booths and decoy.Name=="NotABooth")
p=mkplayer(M); M.Players.PlayerAdded.Fire(p)
prompts[0].Triggered.Fire(p)
owned=p.FindFirstChild(p, "OwnedBooth")
check("adopted booth is CLAIMABLE", owned is not None and owned.Value is not None)

print("\n=== self healing: missing Booths folder ===")
L2=_LR(unpack_returned_tuples=True); g2=L2.globals()
M2=L2.execute(open(MOCK).read()); M2.install(g2,None)
L2.execute("""
local M = ...
local MPS = M.MPS
MPS.PlayerOwnsAsset = function(a1,a2,a3) return false end
""", M2)
M2.owned = L2.eval("{}")
# delete the pre-made folder so the server must create it
M2.booths.Parent = None
WS2 = M2.Workspace if hasattr(M2,'Workspace') else None
ok_run=True
try:
    L2.execute(open(SERVER).read())
except Exception as e:
    ok_run=False
    print("   error:", str(e)[:120])
check("server survives a missing Booths folder (no infinite WaitForChild)", ok_run)

print("\n=== boombox built at run time ===")
L3,M3,bs3 = boot(owned=(BOOMBOX,))
tool = M3.ServerStorage.FindFirstChild(M3.ServerStorage, "Boombox")
check("tool auto-created in ServerStorage", tool is not None)
if tool is not None:
    h=tool.FindFirstChild(tool, "Handle")
    check("has Handle", h is not None)
    check("has Sound on Handle", h is not None and h.FindFirstChild(h, "BoomboxSound") is not None)
    check("tool has NO child scripts (Source cannot be set at run time)",
          tool.FindFirstChild(tool, "BoomboxServer") is None and tool.FindFirstChild(tool, "BoomboxClient") is None)
check("shared BoomboxRemote created in ReplicatedStorage",
      M3.RS.FindFirstChild(M3.RS, "BoomboxRemote") is not None)

print()
bad=[x for x in ok if not x]
print("%d/%d checks passed"%(len(ok)-len(bad),len(ok)))
sys.exit(1 if bad else 0)
