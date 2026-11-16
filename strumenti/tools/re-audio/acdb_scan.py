#!/usr/bin/env python3
"""Inventario di un file ACDB AudioReach (Qualcomm): moduli per sottografo e parametri di calibrazione.
usage: acdb_scan.py acdb_cal.acdb ids.txt [out.json]
Formato dedotto dal parser open source audioreach-graphservices (chunk HEAD, SGIT, CDDE, CDDO, POOL...)."""
import json, struct, sys
from collections import Counter, defaultdict

data = open(sys.argv[1], "rb").read()
names = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 2:
        names.setdefault(int(p[1], 16), p[0])


def nm(v):
    return names.get(v, f"0x{v:08X}")


def u32(o):
    return struct.unpack_from("<I", data, o)[0]


chunks, o = {}, 12
while o < len(data) - 8:
    tag = data[o:o + 4].decode("latin1"); sz = u32(o + 4)
    chunks[tag] = (o + 8, sz); o += 8 + sz

# --- SGIT: sottografo -> processori -> (module_id, instance_id)
off, sz = chunks["SGIT"]; end = off + sz
n = u32(off); p = off + 4
iid2mid, sg_mods = {}, {}
for _ in range(n):
    sg, pc, size = struct.unpack_from("<3I", data, p); p += 12
    q = p; mods = []
    for _ in range(pc):
        pd, mc = struct.unpack_from("<2I", data, q); q += 8
        for _ in range(mc):
            a, b = struct.unpack_from("<2I", data, q); q += 8
            mid, iid = (a, b) if (a >> 24) in (0x07, 0x10, 0x08) else (b, a)
            mods.append((mid, iid)); iid2mid[iid] = mid
    sg_mods[sg] = mods; p += size
print(f"sottografi: {len(sg_mods)}  istanze di moduli: {len(iid2mid)}")
cnt = Counter(m for mods in sg_mods.values() for m, _ in mods)
print("moduli piu' usati:", ", ".join(f"{nm(m)}x{c}" for m, c in cnt.most_common(45)))

# --- CDDE / CDDO: definizioni (iid, pid) e offset nel POOL, tabelle parallele
def tables(tag, width):
    off, sz = chunks[tag]; p = off; out = {}
    while p < off + sz:
        n = u32(p); start = p; p += 4
        out[start - off] = [struct.unpack_from("<%dI" % width, data, p + 4 * width * i) for i in range(n)]
        p += 4 * width * n
    return out

defs = tables("CDDE", 2)
dots = tables("CDDO", 1)
pool_off, pool_sz = chunks["POOL"]
print(f"tabelle CDDE: {len(defs)}  CDDO: {len(dots)}  POOL: {pool_sz} byte")
# le coppie (offset_def, offset_dot) stanno nella tabella di ricerca CDLU: le riconosco perche' entrambi
# gli offset coincidono con l'inizio di una tabella e i conteggi sono uguali
lu_off, lu_sz = chunks["CDLU"]
seen_pairs, pairs = set(), []
for p in range(lu_off, lu_off + lu_sz - 8, 4):
    a, b = struct.unpack_from("<2I", data, p)
    if a in defs and b in dots and len(defs[a]) == len(dots[b]) and (a, b) not in seen_pairs:
        seen_pairs.add((a, b))
        pairs += [(iid, pid, off[0]) for (iid, pid), off in zip(defs[a], dots[b])]
print(f"coppie def/dot trovate in CDLU: {len(seen_pairs)}  parametri di calibrazione: {len(pairs)}")
rec = defaultdict(set)
for iid, pid, po in pairs:
    if po < pool_sz:
        size = u32(pool_off + po)
        rec[(iid2mid.get(iid, 0), pid)].add((iid, po, size))
print("\nMODULO / PARAMETRO / n.varianti / dimensioni")
for (mid, pid), v in sorted(rec.items(), key=lambda kv: (nm(kv[0][0]), nm(kv[0][1]))):
    sizes = sorted({s for _, _, s in v})
    print(f"  {nm(mid):34s} {nm(pid):46s} {len(v):4d}  {sizes[:6]}")
if len(sys.argv) > 3:
    json.dump({"chunks": chunks, "iid2mid": {str(k): v for k, v in iid2mid.items()},
               "sg": {str(k): v for k, v in sg_mods.items()},
               "params": [(iid, iid2mid.get(iid, 0), pid, po, u32(pool_off + po) if po < pool_sz else -1) for iid, pid, po in pairs],
               "pool_off": pool_off}, open(sys.argv[3], "w"))
