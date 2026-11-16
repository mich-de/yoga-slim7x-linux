#!/bin/bash
# Seconda passata: decodifica della taratura del modulo vendor 0x0701000B (parametro 0x0800137B) del Yoga.
# Salva il blob e stampa: scalari iniziali e risposta delle cascate di biquad (float b0 b1 b2 a0 a1 a2, fs presunta 48 kHz).
T=/mnt/d/linux/repo/strumenti/tools/re-audio
A=$(ls /mnt/d/linux/repo/strumenti/audio/windows-driver/qcacsp_idea4001*/acdb_cal.acdb)
[ -s /tmp/acdb.json ] || python3 $T/acdb_scan.py "$A" $T/ids.txt /tmp/acdb.json > /dev/null
python3 -I - /tmp/acdb.json "$A" "${1:-/tmp/vendor0b.bin}" <<'EOF'
import json, struct, sys, math, cmath
j = json.load(open(sys.argv[1])); d = open(sys.argv[2], 'rb').read()
o, pool = 12, None
while o < len(d) - 8:
    if d[o:o+4] == b'POOL': pool = o + 8
    o += 8 + struct.unpack_from('<I', d, o + 4)[0]
blobs = {}
for iid, mid, pid, po, size in j["params"]:
    if mid == 0x0701000B and pid == 0x0800137B: blobs[iid] = d[pool + po + 4: pool + po + 4 + size]
b = blobs[0x4AB0]; open(sys.argv[3], 'wb').write(b)
print("istanze: %d, tarature distinte: %d, dimensione %d" % (len(blobs), len(set(blobs.values())), len(b)))
n = len(b) // 4; f = struct.unpack_from('<%df' % n, b); u = struct.unpack_from('<%dI' % n, b)
print("scalari non nulli nei primi 1100 byte (offset:valore):")
print("  " + ' '.join('%d:%s' % (i * 4, ('%g' % f[i]) if 1e-6 < abs(f[i]) < 1e7 else '0x%x' % u[i]) for i in range(275) if u[i]))
FS = 48000.0; FQ = (40, 80, 150, 300, 600, 1000, 2000, 2400, 3000, 5000, 8000, 12000, 16000)
def isbq(i):
    if i + 6 > n: return False
    c = f[i:i + 6]
    return c[3] == 1.0 and all(math.isfinite(x) and abs(x) < 64 for x in c) and abs(c[4]) <= 2.0001 and abs(c[5]) <= 1.0001 and any(c[:3])
def H(c, fr):
    z = cmath.exp(-2j * math.pi * fr / FS)
    return (c[0] + c[1] * z + c[2] * z * z) / (c[3] + c[4] * z + c[5] * z * z)
i = 0; casc = []
while i < n:
    if isbq(i):
        s = i; secs = []
        while isbq(i): secs.append(f[i:i + 6]); i += 6
        casc.append((s * 4, secs))
    else: i += 1
print("cascate di biquad trovate: %d (sezioni totali %d)" % (len(casc), sum(len(s) for _, s in casc)))
print("  offset sez.attive  dB a Hz: " + ' '.join('%5d' % x for x in FQ))
shown = 0
for off, secs in casc:
    act = [c for c in secs if not (c[0] == 1.0 and c[1] == 0 and c[2] == 0 and c[4] == 0 and c[5] == 0)]
    if not act: continue
    r = [20 * math.log10(max(1e-9, abs(math.prod(H(c, fr) for c in act)))) for fr in FQ]
    print("  %6d  %2d/%-2d            %s" % (off, len(act), len(secs), ' '.join('%5.1f' % x for x in r)))
    shown += 1
    if shown >= 26: print("  ..."); break
EOF
