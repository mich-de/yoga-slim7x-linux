#!/usr/bin/env python3
# Decodifica le risposte "q6apm getcfg" del parametro 0x080011F8 (stato della calibrazione di SP_VI).
#   sudo dmesg | python3 statovi.py
# Parole: esito, modulo, parametro, dimensione, errore, canali, STATO, R0 in Q24 per altoparlante.
import re
import sys

NOMI = {1: "porta V/I ferma", 2: "riscaldamento", 3: "in corso", 4: "RIUSCITA", 5: "fallita",
        6: "in attesa di V/I", 7: "attesa V/I scaduta", 8: "V/I troppo bassi"}


def riga(t, w):
    if len(w) < 7 or w[2] != 0x080011F8:
        return None
    r0 = "  ".join("%.3f" % (x / 2**24) for x in w[7:7 + w[5]])
    return "%10s s  esito %d  stato %d (%s)  R0 ohm: %s" % (t, w[0], w[6], NOMI.get(w[6], "?"), r0)


def decodifica(righe):
    t, w, out = None, [], []
    for r in righe:
        m = re.search(r"\[\s*([\d.]+)\].*q6apm getcfg: (\w+): (.*)", r)
        if not m:
            continue
        if m.group(2) == "00000000":
            out.append(riga(t, w))
            t, w = m.group(1), []
        w += [int(x, 16) for x in m.group(3).split()]
    out.append(riga(t, w))
    return [x for x in out if x]


if __name__ == "__main__":
    # autoverifica su una risposta vera (stato 7, 4 canali) con R0 finti di 4 e 3,5 ohm
    prova = ["[ 1.5] k: q6apm getcfg: 00000000: 00000000 00004121 080011f8 00000018",
             "[ 1.5] k: q6apm getcfg: 00000010: 00000000 00000004 00000007 04000000",
             "[ 1.5] k: q6apm getcfg: 00000020: 03800000 00000000 00000000 00000000"]
    assert decodifica(prova) == ["       1.5 s  esito 0  stato 7 (attesa V/I scaduta)  "
                                 "R0 ohm: 4.000  3.500  0.000  0.000"], decodifica(prova)
    print("\n".join(decodifica(sys.stdin)) or "nessuna risposta getcfg 0x080011F8")
