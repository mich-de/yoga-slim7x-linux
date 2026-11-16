#!/usr/bin/env python3
"""Per le varianti di calibrazione dei moduli degli altoparlanti mostra le chiavi (CKV) che le selezionano.
usage: acdb_ckv.py acdb_cal.acdb"""
import struct, sys

data = open(sys.argv[1], "rb").read()
u32 = lambda o: struct.unpack_from("<I", data, o)[0]
chunks, o = {}, 12
while o < len(data) - 8:
    chunks[data[o:o + 4].decode("latin1")] = (o + 8, u32(o + 4)); o += 8 + u32(o + 4)


def tables(tag, width):
    off, sz = chunks[tag]; p = off; out = {}
    while p < off + sz:
        n = u32(p); start = p; p += 4
        out[start - off] = [struct.unpack_from("<%dI" % width, data, p + 4 * width * i) for i in range(n)]
        p += 4 * width * n
    return out


defs, dots = tables("CDDE", 2), tables("CDDO", 1)
pool = chunks["POOL"][0]
ka, ks = chunks["CAKT"]
print("CAKT (tabella chiavi):", [hex(u32(ka + 4 * i)) for i in range(ks // 4)])
lu, ls = chunks["CDLU"]
TARGET = {0x4017, 0x4018, 0x4019, 0x4020, 0x4015}
seen = set()
for p in range(lu, lu + ls - 8, 4):
    a, b = struct.unpack_from("<2I", data, p)
    if a in defs and b in dots and len(defs[a]) == len(dots[b]) and (a, b) not in seen:
        seen.add((a, b))
        hit = [(iid, pid, off[0]) for (iid, pid), off in zip(defs[a], dots[b]) if iid in TARGET]
        if not hit:
            continue
        prev = [hex(u32(p - 4 * k)) for k in range(6, 0, -1)]
        desc = []
        for iid, pid, po in hit:
            size = u32(pool + po)
            blob = data[pool + po + 4: pool + po + 4 + size]
            if pid == 0x08001022:
                n = u32(pool + po + 4); q = 4; parts = []
                for _ in range(n):
                    lsb, msb, _r, ns = struct.unpack_from("<IIHH", blob, q)
                    parts.append(f"mask=0x{lsb:X}/{msb:X}:{ns}bq"); q += 12 + 22 * ns; q = (q + 3) & ~3
                desc.append(f"{iid:X}.CFG[{' '.join(parts)}]")
            elif pid == 0x08001020:
                n = u32(pool + po + 4)
                desc.append(f"{iid:X}.EN[" + " ".join(f"0x{struct.unpack_from('<I', blob, 4 + 12 * i)[0]:X}={struct.unpack_from('<I', blob, 12 + 12 * i)[0]}" for i in range(n)) + "]")
            elif pid == 0x08001006:
                desc.append(f"{iid:X}.GAIN={struct.unpack_from('<H', blob, 0)[0]}")
            elif pid == 0x08001026:
                desc.append(f"{iid:X}.MODEN={u32(pool + po + 4)}")
        print(f"def={a} dot={b} n={len(defs[a])} precedenti={prev}\n    " + "; ".join(desc))
