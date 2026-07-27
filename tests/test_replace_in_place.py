import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rbxl_reader import load, nm
from lupa import LuaRuntime

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA=os.path.join(ROOT,'scripts/ReplaceBooths.commandbar.lua')
I,P = load(os.path.join(ROOT,'rateava2.rbxl'))
ch={}
for a,b in P.items(): ch.setdefault(b,[]).append(a)
ROT={0x02:((1,0,0),(0,1,0),(0,0,1)),0x03:((1,0,0),(0,0,-1),(0,1,0)),
 0x05:((1,0,0),(0,-1,0),(0,0,-1)),0x06:((1,0,0),(0,0,1),(0,-1,0)),
 0x07:((0,1,0),(1,0,0),(0,0,-1)),0x09:((0,0,1),(1,0,0),(0,1,0)),
 0x0a:((0,-1,0),(1,0,0),(0,0,1)),0x0c:((0,0,-1),(1,0,0),(0,-1,0)),
 0x0d:((0,1,0),(0,0,1),(1,0,0)),0x0e:((0,0,-1),(0,1,0),(1,0,0)),
 0x10:((0,-1,0),(0,0,-1),(1,0,0)),0x11:((0,0,1),(0,-1,0),(1,0,0)),
 0x14:((-1,0,0),(0,1,0),(0,0,-1)),0x15:((-1,0,0),(0,0,1),(0,1,0)),
 0x17:((-1,0,0),(0,-1,0),(0,0,1)),0x18:((-1,0,0),(0,0,-1),(0,-1,0)),
 0x19:((0,1,0),(-1,0,0),(0,0,1)),0x1b:((0,0,-1),(-1,0,0),(0,1,0)),
 0x1c:((0,-1,0),(-1,0,0),(0,0,-1)),0x1e:((0,0,1),(-1,0,0),(0,-1,0)),
 0x1f:((0,1,0),(0,0,-1),(-1,0,0)),0x20:((0,0,1),(0,1,0),(-1,0,0)),
 0x22:((0,-1,0),(0,0,1),(-1,0,0)),0x23:((0,0,-1),(0,-1,0),(-1,0,0))}
def mat(r):
    if isinstance(r,int): return ROT.get(r,((1,0,0),(0,1,0),(0,0,1)))
    return (r[0:3],r[3:6],r[6:9])

L=LuaRuntime(unpack_returned_tuples=True); g=L.globals()
S=L.execute(open(os.path.join(ROOT,'tests/studio_mock.lua')).read()); S.install(g)
new,cfnew,v3=S.new,S.cfnew,S.v3
WS=S.Workspace
def mkrot(m):
    t=L.eval("{}")
    for i in range(3):
        for j in range(3): t[i*3+j+1]=float(m[i][j])
    return t
BASEPARTS={'Part','UnionOperation','MeshPart','SpawnLocation','TrussPart','WedgePart','Seat','VehicleSeat'}
def build(ref,parent):
    i=I[ref]; o=new(i['class'], nm(I,ref), parent)
    pr=i['props']
    if 'CFrame' in pr and 'size' in pr:
        (px,py,pz),rot=pr['CFrame']; s=pr['size']
        o.CFrame=cfnew(px,py,pz,mkrot(mat(rot))); o.Size=v3(*s)
    for c in ch.get(ref,[]): build(c,o)
    return o
wsref=[r for r in ch.get(-1,[]) if nm(I,r)=='Workspace'][0]
for c in ch.get(wsref,[]): build(c,WS)

ok=[]
def check(l,c,e=""):
    ok.append(c); print(("PASS  " if c else "FAIL  ")+l+(("   "+e) if e else ""))

src=open(LUA).read()
n_old=sum(1 for c in ch.get(wsref,[]) if nm(I,c)=='Booth')
print("built mock from rateava2.rbxl: %d old booths\n"%n_old)

# DRY RUN
L.execute(src)
out=[S.prints[k] for k in sorted(S.prints.keys())]
warns=[S.warnings[k] for k in sorted(S.warnings.keys())]
print("\n".join(out[:5])); print("  ..."); print("\n".join(out[-2:])); print()
check("dry run destroys nothing", S.destroyed==0, "destroyed=%d"%S.destroyed)
check("dry run finds all 18", any("old booths found: 18" in s for s in out))
check("dry run no warnings", len(warns)==0, str(warns))
check("template auto-detected as boothgood",
      any("boothgood" in s for s in out if "template:" in s), str([s for s in out if "template:" in s]))

# REAL RUN
S.prints=L.eval("{}"); S.warnings=L.eval("{}"); S.destroyed=0
L.execute(src.replace("local DRY_RUN = true","local DRY_RUN = false",1))
out2=[S.prints[k] for k in sorted(S.prints.keys())]
warns2=[S.warnings[k] for k in sorted(S.warnings.keys())]
print("\n".join(out2[-4:])); print()
folder=WS.FindFirstChild(WS,"Booths")
check("Booths folder exists", folder is not None)
kids=list(folder.GetChildren(folder).values()) if folder else []
check("18 new booths in Booths folder", len(kids)==18, str(len(kids)))
check("18 old booths destroyed", S.destroyed==18, "destroyed=%d"%S.destroyed)
check("no warnings on real run", len(warns2)==0, str(warns2))

left=sum(1 for d in WS.GetDescendants(WS).values()
         if d.ClassName=="Model" and d.FindFirstChild(d,"Banner") is not None)
check("no old booths remain", left==0, str(left))

# template untouched
tpl=WS.FindFirstChild(WS,"boothgood")
check("boothgood template still intact in Workspace", tpl is not None and tpl.FindFirstChild(tpl,"Display") is not None)
check("template NOT inside Booths folder", all(k.Name!="boothgood" for k in kids))

# structure
sok=True
for b in kids:
    d=b.FindFirstChild(b,"Display")
    if not d or not d.FindFirstChild(d,"BoothOwner") or not d.FindFirstChild(d,"SurfaceGui"): sok=False
    if not b.FindFirstChild(b,"PartNamePlayer"): sok=False
check("all new booths have Display/BoothOwner/SurfaceGui/PartNamePlayer", sok)

# placement vs original banners
banners=[]
for c in ch.get(wsref,[]):
    if nm(I,c)=='Booth':
        ban=[d for d in ch.get(c,[]) if nm(I,d)=='Banner'][0]
        (bx,by,bz),rot=I[ban]['props']['CFrame']
        banners.append((bx,bz,mat(rot)))
news=sorted([(b.Display.CFrame.X,b.Display.CFrame.Z) for b in kids])
olds=sorted([(b[0],b[1]) for b in banners])
drift=max(math.hypot(a[0]-c[0],a[1]-c[1]) for a,c in zip(olds,news))
check("new booths at old banner XZ (drift %.4f)"%drift, drift<0.01)

# ground alignment
def bbox_ref(ref):
    lo=[1e9]*3
    st=[ref]
    while st:
        x=st.pop(); st+=ch.get(x,[])
        pr=I[x]['props']
        if 'CFrame' in pr and 'size' in pr:
            (px,py,pz),rot=pr['CFrame']; s=pr['size']; m=mat(rot)
            ey=abs(m[1][0])*s[0]/2+abs(m[1][1])*s[1]/2+abs(m[1][2])*s[2]/2
            lo[1]=min(lo[1],py-ey)
    return lo[1]
oldfloors=sorted(bbox_ref(c) for c in ch.get(wsref,[]) if nm(I,c)=='Booth')
def mockfloor(m):
    lo=1e9
    for p in m.GetDescendants(m).values():
        if p.IsA(p,"BasePart") and p.Size is not None:
            s=p.Size; x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22=p.CFrame.components(p.CFrame)
            ey=abs(r10)*s.X/2+abs(r11)*s.Y/2+abs(r12)*s.Z/2
            lo=min(lo,y-ey)
    return lo
newfloors=sorted(mockfloor(b) for b in kids)
gd=max(abs(a-b) for a,b in zip(oldfloors,newfloors))
check("new booths sit on the old floor (max diff %.5f)"%gd, gd<0.02)

# facing flipped
fok=True; worst=1.0
for (bx,bz,m) in banners:
    # match the NEW booth to its ORIGINAL banner by position, not by sort order
    best=None; bestd=1e9
    for b in kids:
        d=math.hypot(b.Display.CFrame.X-bx, b.Display.CFrame.Z-bz)
        if d<bestd: bestd=d; best=b
    ol=(-m[0][2],-m[2][2]); mag=math.hypot(*ol); ol=(ol[0]/mag,ol[1]/mag)
    lv=best.Display.CFrame.LookVector
    dot=ol[0]*lv.X+ol[1]*lv.Z
    worst=min(worst,-dot)
    if dot > -0.95: fok=False
check("new booths face opposite the old banner (FLIP_180), worst=%.4f"%worst, fok)

# idempotent
S.prints=L.eval("{}"); S.warnings=L.eval("{}"); S.destroyed=0
L.execute(src.replace("local DRY_RUN = true","local DRY_RUN = false",1))
w3=[S.warnings[k] for k in sorted(S.warnings.keys())]
check("re-run is a safe no-op", S.destroyed==0 and any("Nothing to replace" in x for x in w3),
      "destroyed=%d %s"%(S.destroyed,w3))
check("still 18 booths after re-run",
      len(list(WS.FindFirstChild(WS,"Booths").GetChildren(WS.FindFirstChild(WS,"Booths")).values()))==18)

print()
bad=[x for x in ok if not x]
print("%d/%d checks passed"%(len(ok)-len(bad),len(ok)))
sys.exit(1 if bad else 0)
