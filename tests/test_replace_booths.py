"""Actually EXECUTE the command-bar Lua script against a mock Studio built from
the real coordinates in the two rbxm files."""
import xml.etree.ElementTree as ET, math, struct, os, sys
from lupa import LuaRuntime

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, '⭐ Rate My Avatar Map Showcase Judge Pose Outfit.rbxm')
TPL = os.path.join(ROOT, 'boothgood.rbxm')
LUA = os.path.join(ROOT, 'scripts/ReplaceBooths.commandbar.lua')

def nm(i):
    for p in i.findall('./Properties/*'):
        if p.get('name') == 'Name': return p.text or ''
    return ''
def prop(i,n):
    for p in i.findall('./Properties/*'):
        if p.get('name') == n: return p
def cfx(item):
    p = prop(item,'CFrame')
    if p is None: return None
    g = lambda n: float(p.find(n).text)
    return [g(x) for x in ('X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22')]
def szx(item):
    p = prop(item,'size')
    if p is None: return None
    g = lambda n: float(p.find(n).text)
    return (g('X'),g('Y'),g('Z'))

ROT_IDS = {
 0x02:((1,0,0),(0,1,0),(0,0,1)),   0x03:((1,0,0),(0,0,-1),(0,1,0)),
 0x05:((1,0,0),(0,-1,0),(0,0,-1)), 0x06:((1,0,0),(0,0,1),(0,-1,0)),
 0x07:((0,1,0),(1,0,0),(0,0,-1)),  0x09:((0,0,1),(1,0,0),(0,1,0)),
 0x0a:((0,-1,0),(1,0,0),(0,0,1)),  0x0c:((0,0,-1),(1,0,0),(0,-1,0)),
 0x0d:((0,1,0),(0,0,1),(1,0,0)),   0x0e:((0,0,-1),(0,1,0),(1,0,0)),
 0x10:((0,-1,0),(0,0,-1),(1,0,0)), 0x11:((0,0,1),(0,-1,0),(1,0,0)),
 0x14:((-1,0,0),(0,1,0),(0,0,-1)), 0x15:((-1,0,0),(0,0,1),(0,1,0)),
 0x17:((-1,0,0),(0,-1,0),(0,0,1)), 0x18:((-1,0,0),(0,0,-1),(0,-1,0)),
 0x19:((0,1,0),(-1,0,0),(0,0,1)),  0x1b:((0,0,-1),(-1,0,0),(0,1,0)),
 0x1c:((0,-1,0),(-1,0,0),(0,0,-1)),0x1e:((0,0,1),(-1,0,0),(0,-1,0)),
 0x1f:((0,1,0),(0,0,-1),(-1,0,0)), 0x20:((0,0,1),(0,1,0),(-1,0,0)),
 0x22:((0,-1,0),(0,0,1),(-1,0,0)), 0x23:((0,0,-1),(0,-1,0),(-1,0,0)),
}

base = open(os.path.join(ROOT,'tests','rbxm_reader.py')).read().split("data = open")[0]
ns={}; exec(base, ns)
R_, lz4, i32, f32 = ns['R'], ns['lz4_decompress'], ns['interleaved_i32'], ns['interleaved_f32']

def parse_bin(path):
    data=open(path,'rb').read()
    r=R_(data); r.read(16); r.u32(); r.u32(); r.read(8)
    classes={}; insts={}; parents={}
    while True:
        name=r.read(4); comp=r.u32(); unc=r.u32(); r.read(4)
        pl=r.read(comp if comp else unc)
        if comp: pl=lz4(pl,unc)
        c=R_(pl)
        if name==b'INST':
            tid=c.u32(); cn=c.str().decode(); c.read(1); cnt=c.u32()
            ids=i32(c.read(4*cnt),cnt); a=0; real=[]
            for v in ids: a+=v; real.append(a)
            classes[tid]=(cn,real)
            for x in real: insts[x]={'class':cn,'props':{}}
        elif name==b'PROP':
            tid=c.u32(); pn=c.str().decode(); pt=c.read(1)[0]
            cn,refs=classes[tid]; cnt=len(refs)
            if pt==0x01:
                for ref,v in zip(refs,[c.str() for _ in range(cnt)]): insts[ref]['props'][pn]=v
            elif pt==0x0E:
                xs=f32(c.read(4*cnt),cnt); ys=f32(c.read(4*cnt),cnt); zs=f32(c.read(4*cnt),cnt)
                for k,ref in enumerate(refs): insts[ref]['props'][pn]=(xs[k],ys[k],zs[k])
            elif pt==0x10:
                rots=[]
                for _ in range(cnt):
                    idb=c.read(1)[0]
                    rots.append(struct.unpack('<9f', c.read(36)) if idb==0 else idb)
                xs=f32(c.read(4*cnt),cnt); ys=f32(c.read(4*cnt),cnt); zs=f32(c.read(4*cnt),cnt)
                for k,ref in enumerate(refs): insts[ref]['props'][pn]=((xs[k],ys[k],zs[k]),rots[k])
        elif name==b'PRNT':
            c.read(1); cnt=c.u32()
            ch=i32(c.read(4*cnt),cnt); pa=i32(c.read(4*cnt),cnt)
            a=0; chi=[]
            for v in ch: a+=v; chi.append(a)
            a=0; par=[]
            for v in pa: a+=v; par.append(a)
            for x,y in zip(chi,par): parents[x]=y
        elif name==b'END\x00': break
    return insts, parents

L = LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
S = L.execute(open(os.path.join(ROOT,'tests','studio_mock.lua')).read())
S.install(g)
new, cfnew, v3 = S.new, S.cfnew, S.v3
WS = S.Workspace

def mkrot(m):
    t = L.eval("{}")
    for i in range(3):
        for j in range(3):
            t[i*3+j+1] = float(m[i][j])
    return t

# ---- build map booths in the mock workspace
root = ET.parse(MAP).getroot()
n_old = 0
for item in root.findall('./Item'):
    if nm(item) != 'Booth':
        continue
    n_old += 1
    model = new("Model", "Booth", WS)
    for c in item.findall('./Item'):
        v = cfx(c); s = szx(c)
        cls = c.get('class')
        part = new(cls if cls in ('Part','UnionOperation','MeshPart') else cls, nm(c), model)
        if v and s:
            m = ((v[3],v[4],v[5]),(v[6],v[7],v[8]),(v[9],v[10],v[11]))
            part.CFrame = cfnew(v[0], v[1], v[2], mkrot(m))
            part.Size = v3(s[0], s[1], s[2])
        for sub in c.findall('./Item'):
            new(sub.get('class'), nm(sub), part)

# ---- build the template in ServerStorage
tpl_i, tpl_p = parse_bin(TPL)
def tnm(i):
    p=i['props'].get('Name',b'?')
    return p.decode() if isinstance(p,bytes) else str(p)
roots = [r for r in tpl_i if tpl_p.get(r,-1)==-1]
tpl_model = new("Model", "Booth", S.ServerStorage)
ref2obj = {}
for ref,i in tpl_i.items():
    if i['class']=='Model': continue
    parent_ref = tpl_p.get(ref,-1)
    obj = new(i['class'], tnm(i), None)
    ref2obj[ref] = obj
for ref,i in tpl_i.items():
    if i['class']=='Model': continue
    o = ref2obj[ref]
    pr = tpl_p.get(ref,-1)
    o.Parent = ref2obj.get(pr, tpl_model)
    if 'CFrame' in i['props'] and 'size' in i['props']:
        (px,py,pz), rot = i['props']['CFrame']
        m = ROT_IDS[rot] if isinstance(rot,int) else (rot[0:3],rot[3:6],rot[6:9])
        o.CFrame = cfnew(px,py,pz, mkrot(m))
        s = i['props']['size']
        o.Size = v3(s[0],s[1],s[2])

print("mock built: %d old booths, template=%s" % (n_old, tpl_model.GetFullName(tpl_model)))
print()

src = open(LUA).read()

# ---------- run 1: DRY RUN
L.execute(src)
out = [S.prints[k] for k in sorted(S.prints.keys())]
print("\n".join(out[:6]))
print("  ...")
print("\n".join(out[-3:]))
dry_destroyed = S.destroyed
booths_folder = WS.FindFirstChild(WS, "Booths")

ok = []
def check(l,c,e=""):
    ok.append(c); print(("PASS  " if c else "FAIL  ")+l+(("   "+e) if e else ""))

print()
check("dry run destroys nothing", dry_destroyed == 0, "destroyed=%d"%dry_destroyed)
check("dry run creates no Booths folder", booths_folder is None)
check("dry run reports all 18", any("would replace 18" in s for s in out))
check("no warnings during dry run", len(S.warnings)==0, str([S.warnings[k] for k in sorted(S.warnings.keys())]))

# ---------- run 2: for real
S.prints = L.eval("{}")
S.warnings = L.eval("{}")
S.destroyed = 0
L.execute(src.replace("local DRY_RUN = true", "local DRY_RUN = false"))
out2 = [S.prints[k] for k in sorted(S.prints.keys())]
print()
print("\n".join(out2[-5:]))
print()

folder = WS.FindFirstChild(WS, "Booths")
check("Booths folder created", folder is not None)
newb = folder.GetChildren(folder) if folder else []
n_new = len(list(newb.values())) if folder else 0
check("18 new booths created", n_new == 18, str(n_new))
check("all 18 old booths destroyed", S.destroyed == 18, "destroyed=%d"%S.destroyed)

remaining = 0
for d in WS.GetDescendants(WS).values():
    if d.ClassName == "Model" and d.FindFirstChild(d, "Banner") is not None:
        remaining += 1
check("no old booths left in workspace", remaining == 0, str(remaining))

# structure + placement of the new ones
struct_ok = True
ys = []
for b in newb.values():
    d = b.FindFirstChild(b, "Display")
    if not d or not d.FindFirstChild(d, "BoothOwner") or not d.FindFirstChild(d, "SurfaceGui"):
        struct_ok = False
    if not b.FindFirstChild(b, "PartNamePlayer"):
        struct_ok = False
    ys.append(d.CFrame.Y)
check("every new booth has Display/BoothOwner/SurfaceGui/PartNamePlayer", struct_ok)

# compare each new booth position against the old banner position
olds = []
for item in ET.parse(MAP).getroot().findall('./Item'):
    if nm(item)=='Booth':
        ban=[c for c in item.findall('./Item') if nm(c)=='Banner'][0]
        v=cfx(ban); olds.append((v[0],v[2]))
news = sorted([(b.Display.CFrame.X, b.Display.CFrame.Z) for b in newb.values()])
olds_s = sorted(olds)
maxd = max(math.hypot(a[0]-b[0], a[1]-b[1]) for a,b in zip(olds_s, news))
check("new booths sit at the old banner XZ (max drift %.4f)"%maxd, maxd < 0.01)

# facing: display LookVector should be opposite the old banner look (FLIP_180)
face_ok = True
for item, b in zip([i for i in ET.parse(MAP).getroot().findall('./Item') if nm(i)=='Booth'],
                   newb.values()):
    ban=[c for c in item.findall('./Item') if nm(c)=='Banner'][0]
    v=cfx(ban)
    oldlook=(-v[5], -v[11]); m=math.hypot(*oldlook)
    oldlook=(oldlook[0]/m, oldlook[1]/m)
    lv=b.Display.CFrame.LookVector
    dot = oldlook[0]*lv.X + oldlook[1]*lv.Z
    if dot > -0.95: face_ok=False   # expect ~ -1 (flipped)
check("new booths face opposite the old banner (FLIP_180 works)", face_ok)

check("no warnings on the real run", len(S.warnings)==0,
      str([S.warnings[k] for k in sorted(S.warnings.keys())]))

# idempotency: running again should find nothing
S.prints = L.eval("{}"); S.warnings = L.eval("{}"); S.destroyed = 0
L.execute(src.replace("local DRY_RUN = true", "local DRY_RUN = false"))
out3=[S.prints[k] for k in sorted(S.prints.keys())]
w3=[S.warnings[k] for k in sorted(S.warnings.keys())]
check("re-running finds 0 old booths (idempotent, does not touch new ones)",
      S.destroyed == 0 and any("Nothing to replace" in x for x in w3),
      "destroyed=%d warns=%s"%(S.destroyed,w3))
after = len(list(WS.FindFirstChild(WS, "Booths").GetChildren(WS.FindFirstChild(WS, "Booths")).values()))
check("still exactly 18 booths after re-run", after == 18, str(after))

print()
bad=[x for x in ok if not x]
print("%d/%d checks passed" % (len(ok)-len(bad), len(ok)))
sys.exit(1 if bad else 0)
