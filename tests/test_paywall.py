from lupa import LuaRuntime
import sys

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(ROOT, 'src/ServerScriptService', 'BoothServer.server.lua')

def boot(owns=False, err=False):
    L = LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    M = L.execute(open(os.path.join(ROOT,'tests','roblox_mock.lua')).read())
    M.install(g, None)
    M.mps.owns = owns
    M.mps.err = err

    # build one booth
    new = M.new
    booths = M.booths
    booth = new("Model", "Booth", booths)
    disp  = new("Part", "Display", booth)
    sg    = new("SurfaceGui", "SurfaceGui", disp)
    new("ImageLabel", "ImageLabel", sg)
    new("TextLabel", "TextLabel", sg)
    att   = new("Attachment", "Attachment", disp)
    prompt = new("ProximityPrompt", "ProximityPrompt", att)
    prompt.Triggered = M.newSignal()
    new("ObjectValue", "BoothOwner", disp)
    pnp = new("Part", "PartNamePlayer", booth)
    sg2 = new("SurfaceGui", "SurfaceGui", pnp)
    new("TextLabel", "TextLabel", sg2)

    L.execute(open(SERVER).read())
    return L, M, booth, prompt

def mkplayer(M, name="Tester", uid=7):
    p = M.new("Player", name, M.Players)
    p.UserId = uid
    return p

def drain(M):
    out = [(m.a, m.b) for m in M.toClient.values()]
    M.toClient = M.new("Folder","x")  # reset not trivial; use lua
    return out

results = []
def check(label, cond, extra=""):
    results.append((label, cond, extra))
    print(("PASS  " if cond else "FAIL  ") + label + ("   " + extra if extra else ""))

# ---------------------------------------------------------------- locked user
L, M, booth, prompt = boot(owns=False)
p = mkplayer(M)
M.Players.PlayerAdded.Fire(p)

msgs = [(m.a, m.b) for m in list(M.toClient.values())]
paywall = [m for m in msgs if m[0] == "PaywallState"]
check("join pushes PaywallState", len(paywall) == 1, str(msgs))
check("locked user reported Owns=false", paywall and paywall[0][1].Owns == False)
check("uses PlayerOwnsAsset (not gamepass)",
      M.mps.calls[1].api == "PlayerOwnsAsset", M.mps.calls[1].api)
check("checks the right asset id 356360", M.mps.calls[1].id == 356360, str(M.mps.calls[1].id))

# claim booth, then try to set an image while locked
prompt.Triggered.Fire(p)
before = booth.Display.SurfaceGui.ImageLabel.Image
M.clock = M.clock + 100
M.remote.OnServerEvent.Fire(p, "ChangeImage", "12345")
after = booth.Display.SurfaceGui.ImageLabel.Image
check("locked ChangeImage is REFUSED", before == after, str(after))
msgs = [(m.a, m.b) for m in list(M.toClient.values())]
check("locked ChangeImage returns ImageError",
      any(m[0] == "ImageError" for m in msgs))

# purchase prompt
M.clock = M.clock + 100
n_before = len(list(M.mps.prompts.values()))
M.remote.OnServerEvent.Fire(p, "PromptPurchase")
prompts = list(M.mps.prompts.values())
check("PromptPurchase opens store", len(prompts) == n_before + 1)
check("uses PromptPurchase API (asset)",
      prompts[-1].api == "PromptPurchase", prompts[-1].api)

# now they buy it
M.mps.owns = True
M.MPS.PromptPurchaseFinished.Fire(p, 356360, True)
msgs = [(m.a, m.b) for m in list(M.toClient.values())]
pw = [m for m in msgs if m[0] == "PaywallState"]
check("purchase pushes Owns=true", pw[-1][1].Owns == True)

M.clock = M.clock + 100
M.remote.OnServerEvent.Fire(p, "ChangeImage", "12345")
check("unlocked ChangeImage APPLIES",
      booth.Display.SurfaceGui.ImageLabel.Image == "rbxassetid://12345",
      str(booth.Display.SurfaceGui.ImageLabel.Image))

# ------------------------------------------------------- wrong-id purchase
L2, M2, booth2, prompt2 = boot(owns=False)
p2 = mkplayer(M2)
M2.Players.PlayerAdded.Fire(p2)
prompt2.Triggered.Fire(p2)
M2.MPS.PromptPurchaseFinished.Fire(p2, 999999, True)   # different item
M2.clock += 100
M2.remote.OnServerEvent.Fire(p2, "ChangeImage", "555")
check("unrelated purchase does NOT unlock",
      booth2.Display.SurfaceGui.ImageLabel.Image != "rbxassetid://555")

# cancelled purchase
L3, M3, booth3, prompt3 = boot(owns=False)
p3 = mkplayer(M3)
M3.Players.PlayerAdded.Fire(p3)
prompt3.Triggered.Fire(p3)
M3.MPS.PromptPurchaseFinished.Fire(p3, 356360, False)  # wasPurchased = false
M3.clock += 100
M3.remote.OnServerEvent.Fire(p3, "ChangeImage", "555")
check("cancelled purchase does NOT unlock",
      booth3.Display.SurfaceGui.ImageLabel.Image != "rbxassetid://555")

# ---------------------------------------------------------- API failure = deny
L4, M4, booth4, prompt4 = boot(owns=True, err=True)
p4 = mkplayer(M4)
M4.Players.PlayerAdded.Fire(p4)
prompt4.Triggered.Fire(p4)
M4.clock += 100
M4.remote.OnServerEvent.Fire(p4, "ChangeImage", "555")
check("API error denies (fails closed)",
      booth4.Display.SurfaceGui.ImageLabel.Image != "rbxassetid://555")

# ---------------------------------------------- non-owner cannot set an image
L5, M5, booth5, prompt5 = boot(owns=True)
owner = mkplayer(M5, "Owner", 1)
other = mkplayer(M5, "Other", 2)
M5.Players.PlayerAdded.Fire(owner)
M5.Players.PlayerAdded.Fire(other)
prompt5.Triggered.Fire(owner)
M5.clock += 100
M5.remote.OnServerEvent.Fire(other, "ChangeImage", "777")
check("non-owner cannot set image on someone else's booth",
      booth5.Display.SurfaceGui.ImageLabel.Image != "rbxassetid://777")

# owner with pass can
M5.clock += 100
M5.remote.OnServerEvent.Fire(owner, "ChangeImage", "777")
check("owner with item can set image",
      booth5.Display.SurfaceGui.ImageLabel.Image == "rbxassetid://777")

# bad ids rejected
for bad in ["abc", "0", "rbxassetid://evil", "1234567890123456789012"]:
    M5.clock += 100
    prev = booth5.Display.SurfaceGui.ImageLabel.Image
    M5.remote.OnServerEvent.Fire(owner, "ChangeImage", bad)
    check("rejects bad id %r" % bad,
          booth5.Display.SurfaceGui.ImageLabel.Image == prev)

# caching: repeated checks shouldn't hammer the API
L6, M6, booth6, prompt6 = boot(owns=True)
p6 = mkplayer(M6)
M6.Players.PlayerAdded.Fire(p6)
prompt6.Triggered.Fire(p6)
M6.step = 0            # freeze clock -> cache valid
base = len(list(M6.mps.calls.values()))
for i in range(5):
    M6.remote.OnServerEvent.Fire(p6, "ChangeImage", str(1000+i))
after_calls = len(list(M6.mps.calls.values()))
check("ownership cached (no API spam)", after_calls - base <= 1,
      "api calls=%d" % (after_calls - base))

print()
bad = [r for r in results if not r[1]]
print("%d/%d passed" % (len(results)-len(bad), len(results)))
sys.exit(1 if bad else 0)
