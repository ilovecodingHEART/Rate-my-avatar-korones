#!/usr/bin/env python3
"""Minimal Roblox binary place (.rbxl/.rbxm) parser -> dumps hierarchy + script sources."""
import sys, os, struct, io, json

import lz4.block
import zstandard

TYPE_STRING = 0x01
TYPE_BOOL = 0x02
TYPE_INT32 = 0x03


def read_chunks(data):
    # header
    assert data[:8] == b"<roblox!", "not a binary rbxl"
    pos = 16
    classcount, inscount = struct.unpack_from("<ii", data, pos)
    pos += 8
    pos += 8  # reserved
    chunks = []
    while pos < len(data):
        name = data[pos:pos + 4]
        comp_len, uncomp_len, _res = struct.unpack_from("<III", data, pos + 4)
        pos += 16
        if comp_len == 0:
            payload = data[pos:pos + uncomp_len]
            pos += uncomp_len
        else:
            raw = data[pos:pos + comp_len]
            pos += comp_len
            if raw[:4] == b"\x28\xb5\x2f\xfd":
                payload = zstandard.ZstdDecompressor().decompress(raw, max_output_size=uncomp_len)
            else:
                payload = lz4.block.decompress(raw, uncompressed_size=uncomp_len)
        chunks.append((name.decode("ascii", "replace").rstrip("\x00"), payload))
        if name == b"END\x00":
            break
    return classcount, inscount, chunks


class R:
    def __init__(self, b):
        self.b = b
        self.p = 0

    def u8(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.b, self.p)[0]
        self.p += 4
        return v

    def string(self):
        n = self.u32()
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def raw(self, n):
        v = self.b[self.p:self.p + n]
        self.p += n
        return v

    def left(self):
        return len(self.b) - self.p


def untransform_i32(u):
    return (u >> 1) ^ (-(u & 1))


def read_interleaved_i32(r, count):
    buf = r.raw(count * 4)
    out = []
    for i in range(count):
        u = (buf[i] << 24) | (buf[count + i] << 16) | (buf[2 * count + i] << 8) | buf[3 * count + i]
        out.append(untransform_i32(u))
    return out


def accumulate(vals):
    out = []
    acc = 0
    for v in vals:
        acc += v
        out.append(acc)
    return out


def parse(path):
    data = open(path, "rb").read()
    classcount, inscount, chunks = read_chunks(data)

    sstr = []
    classes = {}       # classIndex -> {name, referents}
    inst = {}          # referent -> {class, props}
    parents = {}       # child -> parent

    for name, payload in chunks:
        if name == "SSTR":
            r = R(payload)
            r.u32()  # version
            n = r.u32()
            for _ in range(n):
                r.raw(16)
                sstr.append(r.string())
        elif name == "INST":
            r = R(payload)
            ci = r.u32()
            cname = r.string().decode("utf8", "replace")
            r.u8()  # isService
            cnt = r.u32()
            refs = accumulate(read_interleaved_i32(r, cnt))
            classes[ci] = {"name": cname, "refs": refs}
            for ref in refs:
                inst[ref] = {"class": cname, "props": {}}
        elif name == "PRNT":
            r = R(payload)
            r.u8()
            cnt = r.u32()
            childs = accumulate(read_interleaved_i32(r, cnt))
            pars = accumulate(read_interleaved_i32(r, cnt))
            for c, p in zip(childs, pars):
                parents[c] = p

    # second pass for props (need classes populated)
    for name, payload in chunks:
        if name != "PROP":
            continue
        r = R(payload)
        ci = r.u32()
        pname = r.string().decode("utf8", "replace")
        if ci not in classes:
            continue
        refs = classes[ci]["refs"]
        if r.left() == 0:
            continue
        ptype = r.u8()
        try:
            if ptype == TYPE_STRING:
                for ref in refs:
                    inst[ref]["props"][pname] = r.string()
            elif ptype == TYPE_BOOL:
                for ref in refs:
                    inst[ref]["props"][pname] = bool(r.u8())
            elif ptype == TYPE_INT32:
                vals = read_interleaved_i32(r, len(refs))
                for ref, v in zip(refs, vals):
                    inst[ref]["props"][pname] = v
            elif ptype == 0x1C:  # SharedString
                idxs = read_interleaved_i32(r, len(refs))
                for ref, i in zip(refs, idxs):
                    inst[ref]["props"][pname] = sstr[i] if i < len(sstr) else b""
        except Exception as e:
            pass

    children = {}
    for c, p in parents.items():
        children.setdefault(p, []).append(c)
    return inst, parents, children


def name_of(inst, ref):
    v = inst[ref]["props"].get("Name", b"?")
    if isinstance(v, bytes):
        return v.decode("utf8", "replace")
    return str(v)


def path_of(inst, parents, ref):
    parts = []
    seen = set()
    cur = ref
    while cur is not None and cur != -1 and cur in inst and cur not in seen:
        seen.add(cur)
        parts.append(name_of(inst, cur))
        cur = parents.get(cur, -1)
    return "/".join(reversed(parts))


if __name__ == "__main__":
    path = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else None
    inst, parents, children = parse(path)

    def dump(ref, depth):
        i = inst[ref]
        src = i["props"].get("Source")
        extra = ""
        if isinstance(src, bytes) and src:
            extra = f"  [Source {len(src)} bytes]"
        print("  " * depth + f"{name_of(inst, ref)} ({i['class']}){extra}")
        for c in sorted(children.get(ref, []), key=lambda x: name_of(inst, x)):
            dump(c, depth + 1)

    roots = [r for r in inst if parents.get(r, -1) == -1]
    for r in sorted(roots, key=lambda x: name_of(inst, x)):
        dump(r, 0)

    if outdir:
        n = 0
        for ref, i in inst.items():
            src = i["props"].get("Source")
            if isinstance(src, bytes) and src:
                p = path_of(inst, parents, ref)
                safe = p.replace("/", "__").replace(" ", "_")
                ext = {"LocalScript": "client.lua", "ModuleScript": "module.lua"}.get(i["class"], "server.lua")
                fp = os.path.join(outdir, f"{safe}.{ext}")
                os.makedirs(outdir, exist_ok=True)
                open(fp, "wb").write(src)
                n += 1
        print(f"\nwrote {n} scripts to {outdir}", file=sys.stderr)
