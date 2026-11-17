#!/usr/bin/env python3
"""Profilo di Windows degli amplificatori WSA884x: lo costruisce e lo confronta con i registri veri sotto Linux.

  wsa_profilo.py crea <wsa884x.c del kernel> <patch 0063 di geocausa/SP11X1e-audio> <uscita.json>
  sudo wsa_profilo.py confronta <profilo.json>     legge /sys/kernel/debug/regmap/sdw:*/registers

Il profilo e' la sequenza di scritture del driver Windows qcaucd (a freddo, avvio, arresto) ricostruita dal
progetto gemello sul Surface Pro 11; vale per il Yoga perche' il record WSA dell'ACDB e' identico
(vedi audio/protezione/amplificatori/LEGGIMI.txt). Non scrive nulla sugli amplificatori.
"""
import glob
import json
import re
import sys


def indirizzi(sorgente):
    d = {}
    for m in re.finditer(r"#define\s+(WSA884X_\w+)\s+\(?\s*(WSA884X_\w+)\s*\+\s*(0x[0-9a-fA-F]+)\s*\)?", sorgente):
        d[m[1]] = (m[2], int(m[3], 16))
    for m in re.finditer(r"#define\s+(WSA884X_\w+)\s+(0x[0-9a-fA-F]+)\s*$", sorgente, re.M):
        d[m[1]] = (None, int(m[2], 16))

    def addr(n):
        base, off = d[n]
        return off if base is None else addr(base) + off
    return addr


def sequenze(patch, addr):
    seq, cur = {}, None
    for riga in patch.splitlines():
        m = re.match(r"^\+static const struct reg_sequence sp11_windows_(\w+)\[\]", riga)
        if m:
            cur = seq.setdefault(m[1], [])
            continue
        m = re.match(r"^\+\s*\{\s*(WSA884X_\w+),\s*(0x[0-9a-fA-F]+)\s*\}", riga)
        if m and cur is not None:
            cur.append([m[1][8:], addr(m[1]), int(m[2], 16)])
        if riga.startswith("+};"):
            cur = None
    return seq


def vivi():
    amp = {}
    for f in sorted(glob.glob("/sys/kernel/debug/regmap/sdw:*/registers")):
        amp[f.split("/")[-2]] = {int(a, 16): int(v, 16) for a, v in
                                 (r.split(":") for r in open(f)) if re.fullmatch(r"\s*[0-9a-f]{2}\s*", v)}
    return amp


def confronta(profilo):
    amp = vivi()
    if not amp:
        sys.exit("nessun amplificatore in /sys/kernel/debug/regmap (serve root)")
    print("amplificatori:", " ".join(amp))
    for nome, seq in profilo["sequenze"].items():
        finale = {}
        for reg, a, v in seq:
            finale[a] = (reg, v)
        print(f"== {nome}: {len(seq)} scritture; registri diversi da Windows (valore finale):")
        for a, (reg, v) in finale.items():
            lin = [x.get(a) for x in amp.values()]
            if any(x != v for x in lin):
                print("  %-22s 0x%04x  Windows %02x  Linux %s" %
                      (reg, a, v, " ".join("--" if x is None else "%02x" % x for x in lin)))


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "crea":
        seq = sequenze(open(sys.argv[3]).read(), indirizzi(open(sys.argv[2]).read()))
        # autoverifica: i due registri dei sensori confermati nel driver Windows del Yoga
        assert ["ISENSE2", 0x3021, 0x07] in seq["start"] and ["VSENSE1", 0x3020, 0x67] in seq["start"], seq.get("start")
        json.dump({"fonte": "geocausa/SP11X1e-audio patch 0063 (traccia del driver Windows qcaucd sul Surface Pro 11)",
                   "sequenze": seq}, open(sys.argv[4], "w"), indent=1)
        print({k: len(v) for k, v in seq.items()})
    elif len(sys.argv) == 3 and sys.argv[1] == "confronta":
        confronta(json.load(open(sys.argv[2])))
    else:
        sys.exit(__doc__)
