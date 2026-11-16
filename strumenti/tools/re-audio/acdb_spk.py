#!/usr/bin/env python3
"""Sottografi di riproduzione verso gli altoparlanti e loro parametri di calibrazione.
usage: acdb_spk.py acdb.json ids.txt"""
import json, sys
from collections import defaultdict

j = json.load(open(sys.argv[1]))
names = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 2:
        names.setdefault(int(p[1], 16), p[0].replace("MODULE_ID_", "").replace("PARAM_ID_", ""))
# ID noti dal driver Linux (sound/soc/qcom/qdsp6/audioreach.h)
names.update({0x07001023: "CODEC_DMA_SINK", 0x07001024: "CODEC_DMA_SOURCE", 0x070010E2: "SPEAKER_PROTECTION",
              0x070010E3: "SPEAKER_PROTECTION_VI", 0x07001069: "DISPLAY_PORT_SINK", 0x0700100A: "I2S_SINK"})
nm = lambda v: names.get(v, f"0x{v:08X}")
bysg = {int(k): v for k, v in j["sg"].items()}
par = defaultdict(list)
for iid, mid, pid, po, size in j["params"]:
    par[iid].append((pid, size, po))
DSP = {0x07001014, 0x07001045, 0x07001017, 0x07001066, 0x07001022, 0x07001064, 0x07001062, 0x070010E2, 0x070010E3}
shown = 0
for sg, mods in sorted(bysg.items()):
    mids = {m for m, _ in mods}
    if 0x07001023 not in mids and not (mids & {0x070010E2, 0x07001017}):
        continue
    shown += 1
    print(f"\n== sottografo 0x{sg:08X}: " + " > ".join(nm(m) for m, _ in mods))
    for mid, iid in mods:
        ps = par.get(iid, [])
        if not ps or mid in (0x0700101A,):
            continue
        uniq = sorted({(pid, size) for pid, size, _ in ps})
        print(f"   {nm(mid)} [iid 0x{iid:X}] " + ", ".join(f"{nm(p)}:{s}" for p, s in uniq[:14]) + (" ..." if len(uniq) > 14 else ""))
print(f"\nsottografi mostrati: {shown} su {len(bysg)}")
unk = defaultdict(int)
for mods in bysg.values():
    for m, _ in mods:
        if m not in names:
            unk[m] += 1
print("moduli senza nome pubblico:", ", ".join(f"0x{m:08X}x{c}" for m, c in sorted(unk.items(), key=lambda kv: -kv[1])[:30]))
