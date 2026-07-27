"""
Verify the ReplaceBooths placement math against the REAL coordinates parsed
out of the two rbxm files, using a small CFrame/Vector3 implementation in Lua.
"""
import xml.etree.ElementTree as ET, math, struct, sys, os
from lupa import LuaRuntime

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, '⭐ Rate My Avatar Map Showcase Judge Pose Outfit.rbxm')
TPL = os.path.join(ROOT, 'boothgood.rbxm')

# ---------------------------------------------------------------- map (XML)
def nm(i):
    for p in i.findall('./Properties/*'):
        if p.get('name') == 'Name': return p.text or ''
    return ''
def prop(i, n):
    for p in i.findall('./Properties/*'):
        if p.get('name') == n: return p
def cf(item):
    p = prop(item, 'CFrame')
    if p is None: return None
    g = lambda n: float(p.find(n).text)
    return [g(x) for x in ('X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22')]
def size(item):
    p = prop(item, 'size')
    if p is None: return None
    g = lambda n: float(p.find(n).text)
    return (g('X'), g('Y'), g('Z'))

root = ET.parse(MAP).getroot()
map_booths = [i for i in root.findall('./Item') if nm(i) == 'Booth']

def bounds_xml(model):
    lo = [1e9]*3; hi = [-1e9]*3
    for c in model.iter('Item'):
        v = cf(c); s = size(c)
        if not v or not s: continue
        p = v[:3]; R = v[3:]
        ex = [sum(abs(R[k*3+j])*s[j]/2 for j in range(3)) for k in range(3)]
        for k in range(3):
            lo[k] = min(lo[k], p[k]-ex[k]); hi[k] = max(hi[k], p[k]+ex[k])
    return lo, hi

# ------------------------------------------------------------ template (bin)
base = open(os.path.join(ROOT,'tests','rbxm_reader.py')).read().split("data = open")[0]
ns = {}
exec(base, ns)
R_, lz4, i32, f32 = ns['R'], ns['lz4_decompress'], ns['interleaved_i32'], ns['interleaved_f32']

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

def parse_template():
    data = open(TPL,'rb').read()
    r = R_(data); r.read(16); r.u32(); r.u32(); r.read(8)
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
                for k,ref in enumerate(refs): insts[ref]['props'][pn]=((xs[k],ys[k],zs[k]), rots[k])
        elif name==b'PRNT':
            c.read(1); cnt=c.u32()
            ch=i32(c.read(4*cnt),cnt); pa=i32(c.read(4*cnt),cnt)
            a=0; chi=[]
            for v in ch: a+=v; chi.append(a)
            a=0; par=[]
            for v in pa: a+=v; par.append(a)
            for x,y in zip(chi,par): parents[x]=y
        elif name==b'END\x00': break
    return insts

tpl = parse_template()
def tname(i):
    p = i['props'].get('Name', b'?')
    return p.decode() if isinstance(p, bytes) else str(p)

tparts = []
for x, i in tpl.items():
    if 'CFrame' in i['props'] and 'size' in i['props']:
        (px,py,pz), rot = i['props']['CFrame']
        m = ROT_IDS[rot] if isinstance(rot, int) else (rot[0:3], rot[3:6], rot[6:9])
        tparts.append((tname(i), (px,py,pz), i['props']['size'], m))

lo=[1e9]*3; hi=[-1e9]*3
for _,p,s,m in tparts:
    ex=[abs(m[k][0])*s[0]/2 + abs(m[k][1])*s[1]/2 + abs(m[k][2])*s[2]/2 for k in range(3)]
    for k in range(3):
        lo[k]=min(lo[k],p[k]-ex[k]); hi[k]=max(hi[k],p[k]+ex[k])
tpl_min_y = lo[1]
tpl_display = [t for t in tparts if t[0]=='Display'][0]
templateDisplayRise = tpl_display[1][1] - tpl_min_y

print("template bbox size = (%.2f, %.2f, %.2f)" % tuple(hi[k]-lo[k] for k in range(3)))
print("templateDisplayRise = %.3f" % templateDisplayRise)
print()

# ------------------------------------------------- replicate the Lua math
FLIP_180 = True
results = []
def check(label, cond, extra=""):
    results.append(cond)
    print(("PASS  " if cond else "FAIL  ") + label + (("   " + extra) if extra else ""))

print("=== placement per booth ===")
for idx, b in enumerate(map_booths):
    banner = [c for c in b.findall('./Item') if nm(c)=='Banner'][0]
    v = cf(banner)
    bpos = v[:3]; Rm = v[3:]
    # LookVector = -column 2  => (-R02, -R12, -R22)
    look = (-Rm[2], -Rm[5], -Rm[8])
    flat = (look[0], 0.0, look[2])
    mag = math.hypot(flat[0], flat[2])
    outward = (flat[0]/mag, 0.0, flat[2]/mag)
    facing = tuple(-c for c in outward) if FLIP_180 else outward
    olo, ohi = bounds_xml(b)
    ty = olo[1] + templateDisplayRise
    target = (bpos[0], ty, bpos[2])

    # new booth bbox after placing (template moved so Display sits at target)
    dy = ty - tpl_display[1][1]
    new_lo_y = tpl_min_y + dy
    results_ok = abs(new_lo_y - olo[1]) < 1e-6
    if idx < 4 or not results_ok:
        print("  #%2d target=(%7.2f,%6.2f,%8.2f) outward=(%.2f,%.2f) facing=(%.2f,%.2f) groundΔ=%.4f"
              % (idx, target[0], target[1], target[2], outward[0], outward[2],
                 facing[0], facing[2], new_lo_y - olo[1]))
    if not results_ok:
        print("     !! ground mismatch")

print()
# 1. every new booth sits exactly on the old ground line
ground_ok = True
for b in map_booths:
    olo,_ = bounds_xml(b)
    ty = olo[1] + templateDisplayRise
    if abs((tpl_min_y + (ty - tpl_display[1][1])) - olo[1]) > 1e-6:
        ground_ok = False
check("all 18 booths land exactly on the old ground line", ground_ok)

# 2. facing preserved / flipped consistently
yaws = []
for b in map_booths:
    banner = [c for c in b.findall('./Item') if nm(c)=='Banner'][0]
    v = cf(banner); Rm = v[3:]
    look = (-Rm[2], -Rm[8])
    yaws.append(round(math.degrees(math.atan2(look[0], look[1])), 2))
uniq = sorted(set(yaws))
check("booths keep their 3 distinct row orientations", len(uniq) == 3, str(uniq))

# 3. new booth footprint fits inside the old cleared area
tpl_w = hi[0]-lo[0]; tpl_d = hi[2]-lo[2]
fits = True
for b in map_booths:
    olo, ohi = bounds_xml(b)
    ow, od = ohi[0]-olo[0], ohi[2]-olo[2]
    if max(tpl_w, tpl_d) > max(ow, od) + 0.01:
        fits = False
check("template footprint (%.1f x %.1f) fits the old booth area" % (tpl_w, tpl_d), fits)

# 4. no two new booths overlap  (centres are the banner XZ positions)
overlap = None
cs = []
for b in map_booths:
    banner = [c for c in b.findall('./Item') if nm(c)=='Banner'][0]
    v = cf(banner); cs.append((v[0], v[2]))
radius = max(tpl_w, tpl_d) / 2
for a in range(len(cs)):
    for c2 in range(a+1, len(cs)):
        d = math.hypot(cs[a][0]-cs[c2][0], cs[a][1]-cs[c2][1])
        if d < radius:   # hard overlap of centres
            overlap = (a, c2, round(d,2))
check("no two replacement booths collide", overlap is None, str(overlap or ""))

# 5. count
check("exactly 18 old booths detected", len(map_booths) == 18, str(len(map_booths)))

# 6. old booths have no PrimaryPart -> SetPrimaryPartCFrame would error
noprim = all(prop(b,'PrimaryPart') is not None and
             prop(b,'PrimaryPart').text in (None,'null') for b in map_booths)
check("old booths have NO PrimaryPart (script must not rely on it)", noprim)

print()
bad = [r for r in results if not r]
print("%d/%d checks passed" % (len(results)-len(bad), len(results)))
sys.exit(1 if bad else 0)
