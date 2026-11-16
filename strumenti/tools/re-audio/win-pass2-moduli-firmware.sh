#!/bin/bash
# Seconda passata: stato Dolby, APO caricato dal ProxyAPO, tabella dei moduli statici nel firmware ADSP di questo PC.
FR=/mnt/c/Windows/System32/DriverStore/FileRepository
echo '--- Dolby Runtime.xml'; tr -d '\r' < /mnt/c/ProgramData/Dolby/DAX3/Runtime.xml | head -c 600; echo
echo '--- chi registra {FD7F2B29-...} (APO caricato dal ProxyAPO)'
python3 -I - $FR <<'EOF'
import sys, glob, os
needles = [b'FD7F2B29', 'FD7F2B29'.encode('utf-16-le')]
for f in glob.glob(sys.argv[1] + '/*/*.inf'):
    try: d = open(f, 'rb').read()
    except OSError: continue
    if any(n in d or n.lower() in d for n in needles):
        t = d.decode('utf-16', 'ignore') if d[:2] == b'\xff\xfe' else d.decode('latin1')
        hit = [l.strip() for l in t.splitlines() if 'fd7f2b29' in l.lower()][:3]
        print(os.path.basename(os.path.dirname(f)), '|', ' || '.join(h[:150] for h in hit))
EOF
echo '--- firmware ADSP di questo PC'
F=$(find /mnt/d/linux/repo/strumenti/firmware $FR/qcsubsys_ext_adsp8380* -iname 'qcadsp8380.mbn' 2>/dev/null | head -1); echo "$F"; sha256sum "$F" | cut -c1-64
python3 -I - "$F" <<'EOF'
import sys, struct
d = open(sys.argv[1], 'rb').read()
# record di registrazione statica: module_id, get_static_properties, init, classe (16 byte), come documentato da geocausa/SP11X1e-audio
p = d.find(struct.pack('<I', 0x070010E2)); recs = {}
while p != -1:
    if p % 4 == 0:
        mid, gsp, ini, cls = struct.unpack_from('<4I', d, p)
        if gsp >> 24 == ini >> 24 and gsp >> 24 in (0xb0, 0xb1, 0xe0, 0xf0) and cls < 0x40: break
    p = d.find(struct.pack('<I', 0x070010E2), p + 1)
if p == -1: sys.exit("record di 0x070010E2 non trovato")
print("record SPEAKER_PROTECTION a 0x%x: %s" % (p, ' '.join('%08x' % x for x in struct.unpack_from('<4I', d, p))))
hi = struct.unpack_from('<I', d, p + 4)[0] >> 24
ok = lambda q: 0 <= q <= len(d) - 16 and struct.unpack_from('<I', d, q)[0] >> 16 in (0x0700, 0x0701, 0x1000, 0x1001) and struct.unpack_from('<I', d, q + 4)[0] >> 24 == hi and struct.unpack_from('<I', d, q + 12)[0] < 0x40
a = p
while ok(a - 16): a -= 16
b = p
while ok(b + 16): b += 16
tab = [struct.unpack_from('<4I', d, q) for q in range(a, b + 16, 16)]
print("tabella: %d moduli da 0x%x a 0x%x" % (len(tab), a, b))
for want in (0x070010A3, 0x07001097, 0x07001068, 0x070010E4, 0x07001019, 0x070010E2, 0x070010E3):
    r = [t for t in tab if t[0] == want]
    print("  0x%08X: %s" % (want, ' '.join('%08x' % x for x in r[0]) if r else 'NON nella tabella'))
print("classi:", sorted({t[3] for t in tab}))
print("ID:", ' '.join('%X' % t[0] for t in sorted(tab)))
open('/tmp/modtab.txt', 'w').write('\n'.join('%08X %08x %08x %x' % t for t in tab))
EOF
