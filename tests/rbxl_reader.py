import struct, sys
import os as _os
base = open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)),'rbxm_reader.py')).read().split("data = open")[0]
exec(base)

def load(path):
    data = open(path,'rb').read()
    assert data[:8] == b'<roblox!', data[:8]
    r = R(data); r.read(16)
    num_types = r.u32(); num_insts = r.u32(); r.read(8)
    classes={}; instances={}; parents={}
    while True:
        if r.i >= len(r.d): break
        name = r.read(4)
        comp = r.u32(); unc = r.u32(); r.read(4)
        payload = r.read(comp if comp else unc)
        if comp:
            try: payload = lz4_decompress(payload, unc)
            except Exception: continue
        c = R(payload)
        if name == b'INST':
            tid=c.u32(); cname=c.str().decode(); c.read(1); cnt=c.u32()
            ids=interleaved_i32(c.read(4*cnt),cnt); a=0; real=[]
            for v in ids: a+=v; real.append(a)
            classes[tid]=(cname,real)
            for ref in real: instances[ref]={'class':cname,'props':{}}
        elif name == b'PROP':
            tid=c.u32()
            if tid not in classes: continue
            pname=c.str().decode(); pt=c.read(1)[0]
            cname,refs=classes[tid]; cnt=len(refs)
            try:
                if pt==0x01:
                    for ref,v in zip(refs,[c.str() for _ in range(cnt)]):
                        instances[ref]['props'][pname]=v
                elif pt==0x02:
                    for ref in refs: instances[ref]['props'][pname]=bool(c.read(1)[0])
                elif pt==0x03:
                    for ref,v in zip(refs,interleaved_i32(c.read(4*cnt),cnt)):
                        instances[ref]['props'][pname]=v
                elif pt==0x04:
                    for ref,v in zip(refs,interleaved_f32(c.read(4*cnt),cnt)):
                        instances[ref]['props'][pname]=v
                elif pt==0x0E:
                    xs=interleaved_f32(c.read(4*cnt),cnt); ys=interleaved_f32(c.read(4*cnt),cnt); zs=interleaved_f32(c.read(4*cnt),cnt)
                    for k,ref in enumerate(refs): instances[ref]['props'][pname]=(xs[k],ys[k],zs[k])
                elif pt==0x10:
                    rots=[]
                    for _ in range(cnt):
                        idb=c.read(1)[0]
                        rots.append(struct.unpack('<9f', c.read(36)) if idb==0 else idb)
                    xs=interleaved_f32(c.read(4*cnt),cnt); ys=interleaved_f32(c.read(4*cnt),cnt); zs=interleaved_f32(c.read(4*cnt),cnt)
                    for k,ref in enumerate(refs): instances[ref]['props'][pname]=((xs[k],ys[k],zs[k]),rots[k])
                elif pt==0x12:
                    for ref,v in zip(refs,interleaved_u32(c.read(4*cnt),cnt)):
                        instances[ref]['props'][pname]=v
                elif pt==0x13:
                    ids=interleaved_i32(c.read(4*cnt),cnt); a=0; vs=[]
                    for v in ids: a+=v; vs.append(a)
                    for ref,v in zip(refs,vs): instances[ref]['props'][pname]=('REF',v)
            except Exception:
                pass
        elif name == b'PRNT':
            c.read(1); cnt=c.u32()
            ch=interleaved_i32(c.read(4*cnt),cnt); pa=interleaved_i32(c.read(4*cnt),cnt)
            a=0; chi=[]
            for v in ch: a+=v; chi.append(a)
            a=0; par=[]
            for v in pa: a+=v; par.append(a)
            for x,y in zip(chi,par): parents[x]=y
        elif name == b'END\x00':
            break
    return instances, parents

def nm(instances, ref):
    p = instances[ref]['props'].get('Name', b'?')
    return p.decode('utf8','replace') if isinstance(p,bytes) else str(p)
