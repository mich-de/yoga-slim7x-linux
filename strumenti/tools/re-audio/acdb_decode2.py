#!/usr/bin/env python3
"""Decodifica i parametri della catena altoparlanti (Windows, DSP Qualcomm) dal file ACDB.
usage: acdb_decode.py acdb_cal.acdb acdb.json [out.json]
Layout dei parametri dagli header pubblici AudioReach (api_msiir.h, mbdrc_api.h, chmixer_api.h, sal_api.h)."""
import cmath, json, math, struct, sys

data = open(sys.argv[1], "rb").read()
j = json.load(open(sys.argv[2]))
POOL = j["pool_off"]
FS = 48000.0
PID = {}
for _ln in open(sys.argv[3]):
    _p = _ln.split()
    if len(_p) == 2:
        PID.setdefault(int(_p[1], 16), _p[0])
P_EN = next(k for k, v in PID.items() if v == "PARAM_ID_MSIIR_TUNING_FILTER_ENABLE")
P_PG = next(k for k, v in PID.items() if v == "PARAM_ID_MSIIR_TUNING_FILTER_PREGAIN")
P_CF = next(k for k, v in PID.items() if v == "PARAM_ID_MSIIR_TUNING_FILTER_CONFIG_PARAMS")
P_GAIN = next(k for k, v in PID.items() if v == "PARAM_ID_GAIN")
CH = {1: "L", 2: "R", 3: "C", 4: "LS", 5: "RS", 6: "LFE", 7: "CS", 8: "LB", 9: "RB", 10: "TS", 12: "TFL", 13: "TFR"}


def blob(po):
    size = struct.unpack_from("<I", data, POOL + po)[0]
    return data[POOL + po + 4: POOL + po + 4 + size]


def chans(lsb, msb):
    m = lsb | (msb << 32)
    return "+".join(CH.get(i, f"ch{i}") for i in range(64) if m >> i & 1) or "nessuno"


def resp(stages, freqs):
    out = []
    for f in freqs:
        z = cmath.exp(-1j * 2 * math.pi * f / FS); h = 1
        for b0, b1, b2, a1, a2 in stages:
            h *= (b0 + b1 * z + b2 * z * z) / (1 + a1 * z + a2 * z * z)
        out.append(20 * math.log10(abs(h)) if abs(h) > 0 else -200)
    return out


FREQS = [40, 80, 150, 300, 600, 1000, 2000, 3000, 4000, 6000, 8000, 12000, 16000]
want = {int(a, 16): n for a, n in (("4015", "GAIN"), ("4017", "MSIIR-1"), ("4018", "MSIIR-2"), ("4019", "MSIIR-3"), ("401E", "MFC"),
                                    ("4020", "IIR_MBDRC"), ("4022", "VOL_CTRL"), ("4023", "CHMIXER"), ("4001", "SAL"), ("4AC9", "CHMIXER-uscita"))}
seen, result = set(), {"msiir": [], "chmixer": [], "mbdrc": [], "gain": [], "limiter": []}
for iid, mid, pid, po, size in sorted(j["params"]):
    if iid not in want or size <= 0:
        continue
    b = blob(po)
    key = (iid, pid, bytes(b))
    if key in seen:
        continue
    seen.add(key)
    tag = f"[{want[iid]} iid 0x{iid:X} pid 0x{pid:08X} {size}B]"
    if pid == P_CF:                      # MSIIR config
        n = struct.unpack_from("<I", b, 0)[0]; p = 4
        for _ in range(n):
            lsb, msb, _r, ns = struct.unpack_from("<IIHH", b, p); p += 12
            co = struct.unpack_from("<%di" % (5 * ns), b, p); p += 20 * ns
            sh = struct.unpack_from("<%dh" % ns, b, p); p += 2 * ns; p = (p + 3) & ~3
            stages = []
            for s in range(ns):
                b0, b1, b2, a1, a2 = (c / 2.0 ** 30 for c in co[5 * s:5 * s + 5])
                k = 2.0 ** (sh[s] - 2)   # numeratore in Q(32 - shift): con shift 2 e' Q30
                stages.append((b0 * k, b1 * k, b2 * k, a1, a2))
            r = resp(stages, FREQS)
            print(f"{tag} canali {chans(lsb, msb)}: {ns} biquad, shift {list(sh)}")
            print("    risposta dB @" + " ".join(f"{f}:{v:+.1f}" for f, v in zip(FREQS, r)))
            result["msiir"].append({"iid": iid, "channels": chans(lsb, msb), "stages": stages})
    elif pid in (P_EN, P_PG):
        n = struct.unpack_from("<I", b, 0)[0]
        for i in range(n):
            lsb, msb, v = struct.unpack_from("<IIi", b, 4 + 12 * i)
            val = f"enable={v}" if pid == P_EN else f"pregain={v / 2.0 ** 27:.4f} ({20 * math.log10(max(v, 1) / 2.0 ** 27):+.2f} dB)"
            print(f"{tag} canali {chans(lsb, msb)}: {val}")
    elif pid == 0x0800101F:
        try:
            nt = struct.unpack_from("<I", b, 0)[0]; p = 4
            if 0 < nt < 8:
                for _ in range(nt):
                    no, ni = struct.unpack_from("<HH", b, p); p += 4
                    om = struct.unpack_from("<%dH" % no, b, p); p += 2 * no
                    im = struct.unpack_from("<%dH" % ni, b, p); p += 2 * ni
                    c = struct.unpack_from("<%dh" % (no * ni), b, p); p += 2 * no * ni; p = (p + 3) & ~3
                    rows = [[round(c[o * ni + i] / 16384.0, 3) for i in range(ni)] for o in range(no)]
                    print(f"{tag} matrice {ni} ingressi {[CH.get(x, x) for x in im]} -> {no} uscite {[CH.get(x, x) for x in om]}: {rows}")
                    result["chmixer"].append({"iid": iid, "in": im, "out": om, "coeff": rows})
            else:
                print(f"{tag} u16: {list(struct.unpack_from('<%dH' % (size // 2), b, 0))[:24]}")
        except struct.error:
            print(f"{tag} grezzo: {b[:48].hex()}")
    elif want[iid] == "IIR_MBDRC" and size == 128:
        nb, lm, ld, lw, nc = struct.unpack_from("<5I", b, 0)
        print(f"{tag} bande={nb} limiter_mode={lm} limiter_delay={ld} winlen={lw} config={nc} drc_delay={struct.unpack_from('<I', b, 20)[0]}")
        print("    i16:", list(struct.unpack_from("<%dh" % ((size - 24) // 2), b, 24)))
        result["mbdrc"].append(b.hex())
    elif want[iid] == "IIR_MBDRC":
        print(f"{tag} u32: {list(struct.unpack_from('<%dI' % (size // 4), b, 0))}")
    elif want[iid] == "GAIN" and size == 4 and pid == P_GAIN:
        g = struct.unpack_from("<H", b, 0)[0]
        print(f"{tag} gain Q13={g} ({20 * math.log10(max(g, 1) / 8192.0):+.2f} dB)")
        result["gain"].append(g)
    else:
        vals = list(struct.unpack_from("<%di" % (size // 4), b, 0)) if size % 4 == 0 else b.hex()
        print(f"{tag} i32: {vals if not isinstance(vals, list) else vals[:16]}")
        if want[iid] == "SAL":
            result["limiter"].append(vals)
if len(sys.argv) > 4:
    json.dump(result, open(sys.argv[4], "w"), indent=1)
