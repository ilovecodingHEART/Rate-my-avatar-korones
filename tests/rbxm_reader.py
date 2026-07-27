import struct, sys

def lz4_decompress(src, uncomp_size):
    dst = bytearray()
    i = 0
    while i < len(src):
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1
                lit += b
                if b != 255: break
        dst += src[i:i+lit]; i += lit
        if i >= len(src): break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1
                ml += b
                if b != 255: break
        ml += 4
        start = len(dst) - off
        for j in range(ml):
            dst.append(dst[start + j])
    return bytes(dst)

class R:
    def __init__(self, d): self.d=d; self.i=0
    def read(self,n):
        b=self.d[self.i:self.i+n]; self.i+=n; return b
    def u32(self): return struct.unpack('<I', self.read(4))[0]
    def i32(self): return struct.unpack('<i', self.read(4))[0]
    def str(self):
        n=self.u32(); return self.read(n)

def untransform_i32(v):
    return (v >> 1) ^ (-(v & 1))

def interleaved_i32(buf, count):
    out=[]
    for i in range(count):
        v = (buf[i] << 24) | (buf[count+i] << 16) | (buf[2*count+i] << 8) | buf[3*count+i]
        out.append(untransform_i32(v))
    return out

def interleaved_u32(buf, count):
    out=[]
    for i in range(count):
        v = (buf[i] << 24) | (buf[count+i] << 16) | (buf[2*count+i] << 8) | buf[3*count+i]
        out.append(v)
    return out

def interleaved_f32(buf,count):
    out=[]
    for i in range(count):
        v = (buf[i] << 24) | (buf[count+i] << 16) | (buf[2*count+i] << 8) | buf[3*count+i]
        v = ((v >> 1) | ((v & 1) << 31)) & 0xFFFFFFFF
        out.append(struct.unpack('<f', struct.pack('<I', v))[0])
    return out

data = open(sys.argv[1],'rb').read()
assert data[:8] == b'<roblox!'
r = R(data)
r.read(16)  # magic + version
num_types = r.u32(); num_insts = r.u32()
r.read(8)
classes = {}
instances = {}
parents = {}
props = {}

while True:
    name = r.read(4)
    comp = r.u32(); uncomp = r.u32(); r.read(4)
    payload = r.read(comp if comp else uncomp)
    if comp:
        payload = lz4_decompress(payload, uncomp)
    c = R(payload)
    if name == b'INST':
        tid = c.u32(); cname = c.str().decode(); c.read(1)
        cnt = c.u32()
        ids = interleaved_i32(c.read(4*cnt), cnt)
        acc=0; real=[]
        for v in ids:
            acc+=v; real.append(acc)
        classes[tid] = (cname, real)
        for ref in real: instances[ref] = {'class': cname, 'props': {}}
    elif name == b'PROP':
        tid = c.u32(); pname = c.str().decode(); ptype = c.read(1)[0]
        cname, refs = classes[tid]
        cnt = len(refs)
        try:
            if ptype == 0x01:  # string
                vals = [c.str() for _ in range(cnt)]
            elif ptype == 0x02:
                vals = [bool(c.read(1)[0]) for _ in range(cnt)]
            elif ptype == 0x03:
                vals = interleaved_i32(c.read(4*cnt), cnt)
            elif ptype == 0x04:
                vals = interleaved_f32(c.read(4*cnt), cnt)
            elif ptype == 0x05:
                vals = [struct.unpack('<d', c.read(8))[0] for _ in range(cnt)]
            elif ptype == 0x1D or ptype == 0x13:  # ref / enum-ish
                if ptype == 0x13:
                    vals = interleaved_u32(c.read(4*cnt), cnt)
                else:
                    ids = interleaved_i32(c.read(4*cnt), cnt)
                    acc=0; vals=[]
                    for v in ids:
                        acc+=v; vals.append(acc)
            else:
                vals = ['<type 0x%02x>'%ptype]*cnt
        except Exception as e:
            vals = ['<err %s>'%e]*cnt
        for ref, v in zip(refs, vals):
            instances[ref]['props'][pname] = v
    elif name == b'PRNT':
        c.read(1)
        cnt = c.u32()
        ch = interleaved_i32(c.read(4*cnt), cnt)
        pa = interleaved_i32(c.read(4*cnt), cnt)
        acc=0; chi=[]
        for v in ch: acc+=v; chi.append(acc)
        acc=0; par=[]
        for v in pa: acc+=v; par.append(acc)
        for a,b in zip(chi,par): parents[a]=b
    elif name == b'END\x00':
        break

def nm(ref):
    p = instances[ref]['props'].get('Name', b'?')
    return p.decode() if isinstance(p,bytes) else str(p)

children = {}
for ch,pa in parents.items():
    children.setdefault(pa, []).append(ch)

def dump(ref, ind=0):
    inst = instances[ref]
    print('  '*ind + '%s [%s]' % (nm(ref), inst['class']))
    for k,v in sorted(inst['props'].items()):
        if k == 'Name': continue
        if isinstance(v, bytes):
            try: v = v.decode('utf8')
            except: v = repr(v[:60])
        if isinstance(v,str) and len(v)>200: v=v[:200]+'...'
        if str(v).startswith('<type'): continue
        print('  '*ind + '    .%s = %r' % (k, v))
    for c in sorted(children.get(ref,[]), key=nm):
        dump(c, ind+1)

for ref in sorted(children.get(-1, []), key=nm):
    dump(ref)
