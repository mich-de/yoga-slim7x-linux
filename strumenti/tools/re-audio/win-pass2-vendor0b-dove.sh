#!/bin/bash
# Seconda passata: dove l'ACDB del Yoga usa i moduli "vendor" 0x0701000B / 0x0701000A e che parametri hanno.
T=/mnt/d/linux/repo/strumenti/tools/re-audio
A=$(ls /mnt/d/linux/repo/strumenti/audio/windows-driver/qcacsp_idea4001*/acdb_cal.acdb)
python3 $T/acdb_scan.py "$A" $T/ids.txt /tmp/acdb.json > /dev/null || exit 1
python3 -I - /tmp/acdb.json "$A" $T/ids.txt <<'EOF'
import json, struct, sys, math
from collections import defaultdict
j = json.load(open(sys.argv[1])); d = open(sys.argv[2], 'rb').read()
names = {}
for ln in open(sys.argv[3]):
    p = ln.split()
    if len(p) == 2: names.setdefault(int(p[1], 16), p[0].replace("MODULE_ID_", "").replace("PARAM_ID_", ""))
names.update({0x07001023: "CODEC_DMA_SINK", 0x07001024: "CODEC_DMA_SOURCE", 0x070010E2: "SPK_PROT", 0x070010E3: "SPK_PROT_VI",
              0x07001019: "SOFT_PAUSE", 0x070010E4: "CPS_ROUTER", 0x0701000B: "**VENDOR_0B**", 0x0701000A: "**VENDOR_0A**"})
nm = lambda v: names.get(v, "0x%X" % v)
o, pool = 12, None
while o < len(d) - 8:
    t, s = d[o:o+4], struct.unpack_from('<I', d, o + 4)[0]
    if t == b'POOL': pool = o + 8
    o += 8 + s
par = defaultdict(list)
for iid, mid, pid, po, size in j["params"]: par[(mid, iid)].append((pid, size, po))
V = (0x0701000B, 0x0701000A)
for sg, mods in sorted((int(k), v) for k, v in j["sg"].items()):
    if not any(m in V for m, _ in mods): continue
    print("== sottografo 0x%08X: %s" % (sg, " > ".join(nm(m) for m, _ in mods)))
    for mid, iid in mods:
        if mid not in V: continue
        ps = par.get((mid, iid), []); uniq = defaultdict(int)
        for pid, size, _ in ps: uniq[(pid, size)] += 1
        print("   %s iid 0x%X: %s" % (nm(mid), iid, ", ".join("0x%08X:%dB x%d" % (p, s, c) for (p, s), c in sorted(uniq.items()))))
        seen = set()
        for pid, size, po in sorted(ps, key=lambda x: -x[1]):
            if size < 64 or (pid, size) in seen or len(seen) >= 2: continue
            seen.add((pid, size)); b = d[pool + po + 4: pool + po + 4 + size]
            fl = struct.unpack_from('<%df' % (len(b) // 4), b); iv = struct.unpack_from('<%dI' % (len(b) // 4), b)
            print("     0x%08X %dB primi 20 u32: %s" % (pid, size, ' '.join('%x' % x for x in iv[:20])))
            freq = [(i * 4, round(f, 1)) for i, f in enumerate(fl) if 30 <= f <= 20000 and math.isfinite(f)]
            print("     float fra 30 e 20000 (offset:valore), %d in tutto: %s" % (len(freq), ' '.join('%d:%g' % x for x in freq[:40])))
            db = [(i * 4, round(f, 2)) for i, f in enumerate(fl) if (-60 <= f <= -0.5 or 0.5 <= f < 30) and math.isfinite(f)]
            print("     float tipo dB/rapporti, %d in tutto: %s" % (len(db), ' '.join('%d:%g' % x for x in db[:40])))
EOF
