#!/usr/bin/env python3
"""Yoga Slim 7x: porta a 100 kHz il bus I2C di tastiera e touchpad dentro un device tree.

Su questo portatile (BIOS NHCN62WW) il controller della tastiera non regge i 400 kHz del device tree
ufficiale: la tastiera non parte e blocca anche il touchpad. Questo script cambia la proprieta'
clock-frequency del bus che contiene il nodo keyboard@3a.

Funziona su:
  - un file .dtb                       (x1e80100-lenovo-yoga-slim7x.dtb)
  - un kernel Fedora/Ubuntu "con stub" (vmlinuz / linux): i device tree sono incorporati nel file

Uso:
  python3 patch-dtb-i2c100k.py FILE --check             mostra la frequenza attuale, non modifica nulla
  python3 patch-dtb-i2c100k.py FILE --out NUOVO         scrive una copia corretta
  python3 patch-dtb-i2c100k.py FILE --in-place          corregge il file (salva prima FILE.orig)
  opzioni: --freq 100000 (predefinito)

Nota: un kernel modificato non ha piu' una firma valida, quindi non parte con Secure Boot attivo.
Codice di uscita: 0 = fatto/gia' a posto, 1 = errore, 2 = nessun device tree del Yoga Slim 7x nel file.
"""
import argparse, shutil, struct, sys

MAGIC = b"\xd0\x0d\xfe\xed"
MODEL = b"lenovo,yoga-slim7x"


def scan(blob, base):
    """Ritorna (compatibili_root, [(percorso_bus, offset_assoluto_valore, valore)]) per un FDT."""
    (_m, total, off_struct, off_strings, _a, _b, _c, _d, sz_strings, sz_struct) = struct.unpack(">10I", blob[:40])
    strings = blob[off_strings:off_strings + sz_strings]

    def sname(off):
        return strings[off:strings.index(b"\0", off)].decode()

    p = off_struct
    stack = []          # per ogni nodo aperto: [nome, offset_clock_frequency | None, ha_tastiera]
    root_compat = []
    found = []
    while p < off_struct + sz_struct:
        (tok,) = struct.unpack(">I", blob[p:p + 4]); p += 4
        if tok == 1:
            end = blob.index(b"\0", p); name = blob[p:end].decode(); p = (end + 4) & ~3
            if stack and name == "keyboard@3a":
                stack[-1][2] = True
            stack.append([name, None, False])
        elif tok == 2:
            node = stack.pop()
            if node[2] and node[1] is not None:
                path = "/".join(n[0] for n in stack) + "/" + node[0]
                found.append((path, base + node[1], struct.unpack(">I", blob[node[1]:node[1] + 4])[0]))
        elif tok == 3:
            ln, nameoff = struct.unpack(">II", blob[p:p + 8]); p += 8
            pname = sname(nameoff)
            if pname == "clock-frequency" and ln == 4 and stack:
                stack[-1][1] = p
            if pname == "compatible" and len(stack) == 1:
                root_compat = blob[p:p + ln].rstrip(b"\0").split(b"\0")
            p = (p + ln + 3) & ~3
        elif tok == 4:
            continue
        elif tok == 9:
            break
        else:
            raise ValueError("struttura FDT non valida")
    return root_compat, found


def main():
    ap = argparse.ArgumentParser(description="Yoga Slim 7x: bus I2C di tastiera/touchpad a 100 kHz")
    ap.add_argument("file")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--in-place", action="store_true")
    ap.add_argument("--freq", type=int, default=100000)
    a = ap.parse_args()
    if sum(map(bool, (a.check, a.out, a.in_place))) != 1:
        ap.error("scegli una sola tra --check, --out FILE, --in-place")

    data = bytearray(open(a.file, "rb").read())
    targets, pos = [], 0
    while (pos := data.find(MAGIC, pos)) != -1:
        total = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        if 4096 < total < 4_000_000 and pos + total <= len(data):
            try:
                compat, found = scan(bytes(data[pos:pos + total]), pos)
            except Exception:
                pos += 4; continue
            if MODEL in compat:
                targets += found
            pos += total
        else:
            pos += 4
    if not targets:
        print("Nessun device tree 'lenovo,yoga-slim7x' con il nodo keyboard@3a in questo file.")
        return 2
    changed = 0
    for path, off, val in targets:
        print(f"{path}: clock-frequency = {val} Hz (offset {off})", end="")
        if val != a.freq and not a.check:
            data[off:off + 4] = struct.pack(">I", a.freq); changed += 1
            print(f"  ->  {a.freq} Hz")
        else:
            print("  (gia' a posto)" if val == a.freq else "")
    if a.check:
        return 0
    if a.out:
        open(a.out, "wb").write(data); print(f"Scritto {a.out} ({changed} modifica/e).")
    elif changed:
        shutil.copy2(a.file, a.file + ".orig"); open(a.file, "wb").write(data)
        print(f"Corretto {a.file} ({changed} modifica/e); originale salvato in {a.file}.orig")
    else:
        print("Nulla da fare.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"Errore: {e}"); sys.exit(1)
