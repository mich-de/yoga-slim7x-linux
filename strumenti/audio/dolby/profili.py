#!/usr/bin/env python3
"""Traduce taratura-yoga.json in un testo semplice per il motore: una riga per parametro,
"<profilo> <nome> <n> v1 v2 ...". Il risultato contiene la taratura del portatile: non va pubblicato.
  python3 profili.py audio-auto/dolby/taratura-yoga.json > profili.txt"""
import json
import sys

d = json.load(open(sys.argv[1]))
for nome, prof in d["endpoint"]["internal_speaker"]["profili"].items():
    for k, v in prof["parametri"].items():
        if v is None:
            continue
        v = v if isinstance(v, list) else [v]
        if all(isinstance(x, int) for x in v):
            print(nome, k, len(v), *v)
print("costanti bande48 20", *d["costanti"]["band_20_freq"]["fs_48000"])
for k in ("ieq_detailed", "ieq_balanced", "ieq_warm"):
    print("costanti", k, 20, *d["costanti"][k]["target"])
