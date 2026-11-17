#!/usr/bin/env python3
"""Cerca in un hive del registro di Windows (regf) le chiavi il cui percorso contiene
una delle parole date e ne stampa i valori. Uso: hive_spkr.py SYSTEM parola [parola...]"""
import struct, sys

def main(path, words):
    b = open(path, 'rb').read()
    assert b[:4] == b'regf'
    base = 0x1000
    u16 = lambda o: struct.unpack_from('<H', b, o)[0]
    u32 = lambda o: struct.unpack_from('<I', b, o)[0]
    cell = lambda off: base + off + 4          # salta la dimensione della cella

    def subkeys(off):
        c = cell(off); sig = b[c:c+2]; n = u16(c+2)
        if sig in (b'lf', b'lh'):
            return [u32(c+4+8*i) for i in range(n)]
        if sig == b'li':
            return [u32(c+4+4*i) for i in range(n)]
        if sig == b'ri':
            return [k for i in range(n) for k in subkeys(u32(c+4+4*i))]
        return []

    def name(c, ln, ascii_):
        raw = b[c:c+ln]
        return raw.decode('latin1') if ascii_ else raw.decode('utf-16le', 'replace')

    def values(c):
        n, lst = u32(c+0x24), u32(c+0x28)
        out = []
        if n == 0 or lst == 0xffffffff:
            return out
        l = cell(lst)
        for i in range(n):
            v = cell(u32(l+4*i))
            if b[v:v+2] != b'vk':
                continue
            nl, dl, do, typ, fl = u16(v+2), u32(v+4), u32(v+8), u32(v+0xc), u16(v+0x10)
            nm = name(v+0x14, nl, fl & 1) if nl else '(default)'
            if dl & 0x80000000:
                data = b[v+8:v+8+(dl & 0x7fffffff)]
            else:
                d = cell(do); data = b[d:d+dl]
            out.append((nm, typ, data))
        return out

    def walk(off, path):
        c = cell(off)
        if b[c:c+2] != b'nk':
            return
        nm = name(c+0x4c, u16(c+0x48), u16(c+2) & 0x20)
        p = path + '\\' + nm
        if any(w.lower() in p.lower() for w in words):
            vs = values(c)
            if vs:
                print(p)
                for vn, typ, data in vs:
                    if typ == 4 and len(data) == 4:
                        s = '0x%08x (%d)' % (u32_from(data), u32_from(data))
                    elif typ in (1, 2, 7):
                        s = repr(data.decode('utf-16le', 'replace').rstrip('\0'))
                    else:
                        s = data[:64].hex() + (' ...' if len(data) > 64 else '')
                    print('   %-28s t=%d len=%-5d %s' % (vn, typ, len(data), s))
        if u32(c+0x14) and u32(c+0x1c) != 0xffffffff:
            for k in subkeys(u32(c+0x1c)):
                walk(k, p)

    u32_from = lambda d: struct.unpack('<I', d)[0]
    sys.setrecursionlimit(10000)
    walk(u32(0x24), '')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])
