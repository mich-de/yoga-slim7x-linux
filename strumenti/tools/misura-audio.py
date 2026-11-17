#!/usr/bin/env python3
"""Misure audio del Yoga Slim 7x con i microfoni interni (PipeWire, numpy).
  misura-audio.py toni  CANALI FREQ LIV1,LIV2,...     gradini di tono: livello al microfono e distorsione
  misura-audio.py sweep CANALI F1 F2 LIVELLO [SEC]     risposta in frequenza a terzi d'ottava
  misura-audio.py combo XO TWdB POL LIVELLO [EQ] [EQW] [EQT]
        risposta complessiva dei 4 altoparlanti con una catena simulata: passa-alto 110 Hz, incrocio LR4 a XO Hz,
        tweeter a TWdB con polarita' POL (1 o -1); EQ = filtri a campana "freq:Q:dB,..." (comune, woofer, tweeter)
CANALI = indici PCM separati da virgola (0,1 woofer  2,3 tweeter). Livelli in dBFS (negativi), con tetto di sicurezza.
Suona direttamente sull'uscita ALSA (salta la catena "Altoparlanti potenziati"). Per misurare la catena vera:
  YOGA_SINK=effect_input.yoga_spk misura-audio.py sweep 0,1 150 20000 -42 6     (-42 dBFS: sotto la soglia del compressore)
Serve python3-numpy. Fa rumore per alcuni secondi. Sopra 8 kHz i microfoni interni hanno una risonanza: non fidarsi.
"""
import subprocess, sys, time, wave, os, tempfile
import numpy as np

FS = 48000
SINK = os.environ.get("YOGA_SINK", "alsa_output.platform-sound.HiFi__Speaker__sink")
SRC = "alsa_input.platform-sound.HiFi__Mic__source"
MAXDB = {0: -6.0, 1: -6.0, 2: -12.0, 3: -12.0}   # tetto di sicurezza per canale: niente protezione altoparlanti
SEG, GAP = 0.5, 0.2


def scrivi(path, sig, canali):
    if sig.ndim == 2:
        x = sig
    else:
        x = np.zeros((len(sig), 4))
        for c in canali:
            x[:, c] = sig
    with wave.open(path, "wb") as w:
        w.setnchannels(4); w.setsampwidth(2); w.setframerate(FS)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def leggi(path):
    with wave.open(path, "rb") as w:
        n, ch, sw = w.getnframes(), w.getnchannels(), w.getsampwidth()
        d = np.frombuffer(w.readframes(n), dtype={2: "<i2", 4: "<i4"}[sw]).reshape(-1, ch)
    return d / float(2 ** (8 * sw - 1))


def suona_registra(wav, durata):
    rec = tempfile.mktemp(suffix=".wav", dir=os.path.dirname(wav))
    r = subprocess.Popen(["pw-record", "--target", SRC, "--rate", str(FS), "--channels", "2",
                          "--format", "s32", rec], stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    subprocess.run(["pw-play", "--target", SINK, wav], check=True)
    time.sleep(0.5)
    r.terminate(); r.wait()
    return leggi(rec)


def controlla(canali, livello):
    for c in canali:
        if livello > MAXDB[c]:
            sys.exit(f"livello {livello} dBFS oltre il tetto {MAXDB[c]} del canale {c}")


def toni(canali, f, livelli):
    for l in livelli:
        controlla(canali, l)
    n, g = int(SEG * FS), int(GAP * FS)
    t = np.arange(n) / FS
    fade = np.minimum(1, np.minimum(np.arange(n), n - np.arange(n)) / (0.02 * FS))
    parti, env = [np.zeros(int(0.5 * FS))], [np.zeros(int(0.5 * FS))]
    for l in livelli:
        a = 10 ** (l / 20)
        parti += [a * np.sin(2 * np.pi * f * t) * fade, np.zeros(g)]
        env += [a * fade, np.zeros(g)]
    sig, env = np.concatenate(parti), np.concatenate(env)
    wav = tempfile.mktemp(suffix=".wav")
    scrivi(wav, sig, canali)
    y = suona_registra(wav, len(sig) / FS)
    # allineamento: inviluppo a f (blocchi da 10 ms) contro l'inviluppo atteso
    h = 480
    def inv(x):
        m = len(x) // h
        b = x[:m * h].reshape(m, h)
        k = np.exp(-2j * np.pi * f * np.arange(h) / FS)
        return np.abs(b @ k) / h * 2
    ey, er = inv(y[:, 0]), env[:len(env) // h * h].reshape(-1, h).mean(1)
    lag = int(np.argmax(np.correlate(ey, er, "valid"))) * h if len(ey) >= len(er) else 0
    print(f"# canali {canali} f={f:g} Hz   (dBmic = dB rispetto al fondo scala del microfono)")
    print("# ingresso  mic0    mic1   guadagno  THD%   2a     3a   rumore")
    pos = lag + int(0.5 * FS)
    for l in livelli:
        s = y[pos + n // 5: pos + n - n // 5]
        w = np.hanning(len(s))
        riga = []
        for m in range(2):
            S = np.abs(np.fft.rfft(s[:, m] * w)) / (w.sum() / 2)
            fr = np.fft.rfftfreq(len(s), 1 / FS)
            def picco(fx):
                i = np.argmin(abs(fr - fx))
                return np.sqrt((S[i - 3:i + 4] ** 2).sum() / 1.5)
            fo = picco(f)
            arm = [picco(k * f) for k in range(2, 6) if k * f < FS / 2 - 500]
            riga.append((fo, arm))
        fo, arm = riga[0]
        thd = 100 * np.sqrt(sum(a * a for a in arm)) / fo
        rum = np.median(S[(fr > 300) & (fr < 8000)])
        db = lambda v: 20 * np.log10(max(v, 1e-12))
        print(f"  {l:6.1f}  {db(fo):6.1f}  {db(riga[1][0]):6.1f}   {db(fo) - l:6.1f}  {thd:6.2f} {db(arm[0]) - db(fo):6.1f} "
              f"{db(arm[1]) - db(fo) if len(arm) > 1 else 0:6.1f}  {db(rum):6.1f}")
        pos += n + g


def sweep(canali, f1, f2, livello, T=4.0, catena=None):
    controlla(canali, livello)
    if min(canali) >= 2 and f1 < 800:
        sys.exit("tweeter: mai sotto 800 Hz")
    t = np.arange(int(T * FS)) / FS
    L = np.log(f2 / f1)
    x = 10 ** (livello / 20) * np.sin(2 * np.pi * f1 * T / L * (np.exp(t / T * L) - 1))
    fd = int(0.02 * FS)
    x[:fd] *= np.linspace(0, 1, fd); x[-fd:] *= np.linspace(1, 0, fd)
    sig = np.concatenate([np.zeros(int(0.5 * FS)), x, np.zeros(int(0.3 * FS))])
    if catena:
        S = np.fft.rfft(sig); ff = np.fft.rfftfreq(len(sig), 1 / FS)
        sig4 = np.stack([np.fft.irfft(S * h, len(sig)) for h in catena(ff)], 1)
        if abs(sig4).max() > 10 ** (-6 / 20):
            sys.exit("catena: picco oltre -6 dBFS, abbassa il livello")
        sig = sig4
    wav = tempfile.mktemp(suffix=".wav")
    scrivi(wav, sig, canali)
    y = suona_registra(wav, len(sig) / FS)
    N = 1 << int(np.ceil(np.log2(len(y) + len(x))))
    X = np.fft.rfft(x, N)
    fr = np.fft.rfftfreq(N, 1 / FS)
    banda = (fr >= f1) & (fr <= f2)
    out = []
    for m in range(2):
        H = np.zeros(len(X), complex)
        H[banda] = np.fft.rfft(y[:, m], N)[banda] / X[banda]
        ir = np.fft.irfft(H, N)
        p = int(np.argmax(np.abs(ir[:len(y)])))
        a, b = p - int(0.002 * FS), p + int(0.03 * FS)       # finestra: toglie riflessioni tardive e rumore
        w = np.zeros(N); w[a:b] = np.hanning(2 * (b - a))[b - a:]; w[a:p] = 1
        out.append(np.abs(np.fft.rfft(ir * w, N)))
    print(f"# sweep canali {canali} {f1:g}-{f2:g} Hz a {livello} dBFS: guadagno ingresso->microfono in dB (terzi d'ottava)")
    print("#   Hz     mic0    mic1")
    fc = 1000 * 2 ** (np.arange(-14, 14) / 3)
    for c in fc[(fc >= f1 * 1.06) & (fc <= f2 / 1.06)]:
        s = (fr >= c / 2 ** (1 / 6)) & (fr < c * 2 ** (1 / 6))
        print(f"  {c:6.0f}  " + "  ".join(f"{10 * np.log10((o[s] ** 2).mean() + 1e-20):6.1f}" for o in out))


def bq(tipo, f0, q, g=0.0):
    """Coefficienti RBJ (gli stessi dei filtri bq_* di PipeWire)."""
    A = 10 ** (g / 40); w = 2 * np.pi * f0 / FS; al = np.sin(w) / (2 * q); c = np.cos(w)
    if tipo == "lp": b = [(1 - c) / 2, 1 - c, (1 - c) / 2]; a = [1 + al, -2 * c, 1 - al]
    elif tipo == "hp": b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]; a = [1 + al, -2 * c, 1 - al]
    elif tipo == "pk": b = [1 + al * A, -2 * c, 1 - al * A]; a = [1 + al / A, -2 * c, 1 - al / A]
    return np.array(b) / a[0], np.array(a) / a[0]


def H(ff, sezioni):
    z = np.exp(-2j * np.pi * ff / FS); h = np.ones(len(ff), complex)
    for b, a in sezioni:
        h *= (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    return h


def catena(xo, tw_db, pol, hp=110.0, eq=(), eqw=(), eqt=()):
    """Catena lineare simulata: HP -> EQ comune -> incrocio LR4 a xo -> woofer (0,1) e tweeter (2,3)."""
    def f(ff):
        com = H(ff, [bq("hp", hp, 0.707)] + [bq("pk", *e) for e in eq])
        w = com * H(ff, [bq("lp", xo, 0.707)] * 2 + [bq("pk", *e) for e in eqw])
        t = com * H(ff, [bq("hp", xo, 0.707)] * 2 + [bq("pk", *e) for e in eqt]) * pol * 10 ** (tw_db / 20)
        return [w, w, t, t]
    return f


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 4:
        sys.exit(__doc__)
    ch = [int(c) for c in a[1].split(",")] if a[0] != "combo" else []
    if a[0] == "toni":
        toni(ch, float(a[2]), [float(v) for v in a[3].split(",")])
    elif a[0] == "sweep":
        sweep(ch, float(a[2]), float(a[3]), float(a[4]), float(a[5]) if len(a) > 5 else 4.0)
    elif a[0] == "combo":   # combo XO TWdB POL LIVELLO ["f:Q:g,..." eq comune] ["..." eq woofer] ["..." eq tweeter]
        pe = lambda t: [tuple(float(v) for v in e.split(":")) for e in t.split(",") if e]
        e = [pe(a[k]) if len(a) > k else [] for k in (5, 6, 7)]
        sweep([0, 1, 2, 3], 150, 20000, float(a[4]), 6.0, catena(float(a[1]), float(a[2]), float(a[3]), eq=e[0], eqw=e[1], eqt=e[2]))
    else:
        sys.exit(__doc__)
