#!/usr/bin/env python3
"""Compare two flattened device trees property by property. usage: dtb_diff.py a.dtb b.dtb"""
import struct, sys

def parse(blob):
    (_m, _t, off_s, off_str, *_r) = struct.unpack(">10I", blob[:40]); sz_str, sz_s = _r[-2], _r[-1]
    strings = blob[off_str:off_str + sz_str]; props = {}; path = []; p = off_s
    while p < off_s + sz_s:
        (tok,) = struct.unpack(">I", blob[p:p + 4]); p += 4
        if tok == 1:
            e = blob.index(b"\0", p); path.append(blob[p:e].decode()); p = (e + 4) & ~3
        elif tok == 2: path.pop()
        elif tok == 3:
            ln, no = struct.unpack(">II", blob[p:p + 8]); p += 8
            name = strings[no:strings.index(b"\0", no)].decode()
            props["/".join(path) + ":" + name] = blob[p:p + ln]; p = (p + ln + 3) & ~3
        elif tok == 9: break
    return props

a, b = (parse(open(f, "rb").read()) for f in sys.argv[1:3])
def show(v): return v.hex() if len(v) <= 32 else v[:32].hex() + "..."
n = 0
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k):
        n += 1; print(f"{k}\n   A: {show(a[k]) if k in a else '(assente)'}\n   B: {show(b[k]) if k in b else '(assente)'}")
print(f"proprieta' diverse: {n}  (A={len(a)}, B={len(b)})")
