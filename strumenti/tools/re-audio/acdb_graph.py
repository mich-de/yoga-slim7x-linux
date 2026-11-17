#!/usr/bin/env python3
"""Struttura di un sottografo AudioReach dall'ACDB di Windows: moduli, collegamenti dati
e control link. Uso: acdb_graph.py acdb_cal.acdb [0xB0000001]
Cerca nel file i parametri APM 0x08001002 (lista moduli), 0x08001004 (connessioni),
0x08001061 (control link) e tiene quelli che toccano il sottografo chiesto."""
import struct, sys
NAMES = {0x07001002:'GAIN',0x07001010:'SAL',0x07001011:'SPLITTER',0x07001013:'CHMIXER',0x07001014:'MSIIR',
 0x07001015:'MFC',0x0700101A:'LOG',0x0700101B:'VOL',0x07001023:'CODEC_DMA_SINK',0x07001024:'CODEC_DMA_SOURCE',
 0x07001038:'SYNC',0x070010E2:'SP_RX',0x070010E3:'SP_VI',0x070010E4:'CPS_ROUTER',0x07001098:'MUX_DEMUX',0x0701000B:'LENOVO'}
b = open(sys.argv[1], 'rb').read()
sg = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0xB0000001
u = lambda o: struct.unpack_from('<I', b, o)[0]
def hits(pid):
    p = struct.pack('<I', pid); o = b.find(p)
    while o >= 0:
        yield o
        o = b.find(p, o + 4)
mods = {}
for o in hits(0x08001002):
    size, q = u(o+4), o + 8                        # pid, size, payload
    if size > 4096 or u(q) > 16: continue
    n, q = u(q), q + 4
    for _ in range(n):
        s, cont, nm = u(q), u(q+4), u(q+8); q += 12
        if nm > 64: break
        for i in range(nm):
            if s == sg: mods[u(q+4)] = (u(q), cont)
            q += 8
print('MODULI del sottografo %#x: %d' % (sg, len(mods)))
for iid in sorted(mods):
    mid, cont = mods[iid]; print('  %#06x  %#010x %-16s cont %#x' % (iid, mid, NAMES.get(mid, '?'), cont))
nm = lambda i: '%#06x(%s)' % (i, NAMES.get(mods[i][0], '?') if i in mods else 'ext')
seen = set()
for o in hits(0x08001004):
    size, q = u(o+4), o + 8
    n = u(q)
    if size != 4 + 16*n or n > 200: continue
    for i in range(n):
        s, sp, d, dp = struct.unpack_from('<4I', b, q+4+16*i)
        if (s in mods or d in mods) and (s, sp, d, dp) not in seen:
            seen.add((s, sp, d, dp)); print('  DATI  %s:%x -> %s:%x' % (nm(s), sp, nm(d), dp))
seen = set()
for o in hits(0x08001061):
    size, q = u(o+4), o + 8
    end = q + size
    n = u(q); q += 4
    if n > 16 or size > 1024 or end > len(b): continue
    try:
        for i in range(n):
            p1, pp1, p2, pp2, np = struct.unpack_from('<5I', b, q); q += 20
            props = []
            for _ in range(np):
                pid, ps = u(q), u(q+4)
                if q + 8 + ps > end: raise ValueError
                props.append('%#x=%s' % (pid, b[q+8:q+8+ps].hex())); q += 8 + ps
            if (p1 in mods or p2 in mods) and (p1, pp1, p2, pp2) not in seen:
                seen.add((p1, pp1, p2, pp2)); print('  CTRL  %s:%x <-> %s:%x  %s' % (nm(p1), pp1, nm(p2), pp2, ' '.join(props)))
    except (ValueError, struct.error):
        pass
