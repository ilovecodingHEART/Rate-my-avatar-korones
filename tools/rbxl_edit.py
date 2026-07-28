#!/usr/bin/env python3
"""Read a binary .rbxl, replace Script.Source values, write it back out.

Only the PROP chunks that hold a modified "Source" are rebuilt; every other
chunk is copied through byte-for-byte, so nothing else in the place can drift.
"""
import sys, os, struct

import lz4.block

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rbxl_parse import read_chunks, R, parse, path_of, name_of  # noqa: E402

TYPE_STRING = 0x01


def build_chunk(name4, payload, compress=True):
    if compress:
        comp = lz4.block.compress(payload, store_size=False)
        if len(comp) < len(payload):
            return name4 + struct.pack("<III", len(comp), len(payload), 0) + comp
    return name4 + struct.pack("<III", 0, len(payload), 0) + payload


def rewrite(src_path, out_path, replacements):
    """replacements: {instance_path: new_source_bytes}"""
    data = open(src_path, "rb").read()
    _cc, _ic, chunks = read_chunks(data)

    inst, parents, _children = parse(src_path)

    # classIndex -> ordered referents, taken from the INST chunks
    class_refs = {}
    for name, payload in chunks:
        if name != "INST":
            continue
        r = R(payload)
        ci = r.u32()
        r.string()
        r.u8()
        cnt = r.u32()
        buf = r.raw(cnt * 4)
        refs, acc = [], 0
        for i in range(cnt):
            u = (buf[i] << 24) | (buf[cnt + i] << 16) | (buf[2 * cnt + i] << 8) | buf[3 * cnt + i]
            acc += (u >> 1) ^ (-(u & 1))
            refs.append(acc)
        class_refs[ci] = refs

    done = set()
    out = bytearray(data[:32])  # header: magic + version + counts + reserved

    for name, payload in chunks:
        if name != "PROP":
            out += build_chunk(name.encode("ascii").ljust(4, b"\x00"), payload)
            continue

        r = R(payload)
        ci = r.u32()
        pname = r.string()
        if pname != b"Source" or r.left() == 0 or r.u8() != TYPE_STRING:
            out += build_chunk(b"PROP", payload)
            continue

        refs = class_refs.get(ci, [])
        values, touched = [], False
        for ref in refs:
            cur = r.string()
            p = path_of(inst, parents, ref)
            if p in replacements:
                cur = replacements[p]
                done.add(p)
                touched = True
            values.append(cur)

        if not touched:
            out += build_chunk(b"PROP", payload)
            continue

        body = bytearray()
        body += struct.pack("<I", ci)
        body += struct.pack("<I", len(pname)) + pname
        body.append(TYPE_STRING)
        for v in values:
            body += struct.pack("<I", len(v)) + v
        out += build_chunk(b"PROP", bytes(body))

    missing = set(replacements) - done
    if missing:
        raise SystemExit("could not find in place: " + ", ".join(sorted(missing)))

    open(out_path, "wb").write(bytes(out))
    return len(out)


if __name__ == "__main__":
    place = sys.argv[1]
    srcdir = sys.argv[2]
    out = sys.argv[3]

    # <srcdir>/manifest.txt: one "instance/path<TAB>file" per line
    reps = {}
    for line in open(os.path.join(srcdir, "manifest.txt"), encoding="utf8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        ipath, fname = line.split("\t")
        reps[ipath] = open(os.path.join(srcdir, fname), "rb").read()

    n = rewrite(place, out, reps)
    print("wrote %s (%d bytes), %d script(s) replaced" % (out, n, len(reps)))
