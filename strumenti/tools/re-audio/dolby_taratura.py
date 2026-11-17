#!/usr/bin/env python3
# Uso: python3 dolby_taratura.py <xml_altoparlanti> <xml_cuffie> <out.json>   (taratura DAX3 -> JSON leggibile)
import json, re, sys, xml.etree.ElementTree as ET

# unità per nome di parametro: (unità, significato, certezza). "1/16 dB" = valore/16 dB.
# certezza: visto = ricavato dai numeri del file; dedotto = convenzione Dolby DAP, non confermata da documenti.
U = {
 'pregain': ('1/16 dB', 'guadagno prima della catena', 'dedotto'),
 'postgain': ('1/16 dB', 'guadagno dopo la catena', 'dedotto'),
 'system-gain': ('1/16 dB', 'guadagno di sistema', 'dedotto'),
 'calibration-boost': ('1/16 dB', 'guadagno di calibrazione', 'dedotto'),
 'volmax-boost': ('1/16 dB', 'aumento del volume massimo (96 = +6 dB)', 'dedotto'),
 'surround-boost': ('1/16 dB', 'aumento del surround virtualizzato', 'dedotto'),
 'virtualizer-front-speaker-angle': ('gradi', 'angolo virtuale altoparlanti frontali', 'dedotto'),
 'virtualizer-surround-speaker-angle': ('gradi', 'angolo virtuale surround', 'dedotto'),
 'virtualizer-height-speaker-angle': ('gradi', 'angolo virtuale altezza', 'dedotto'),
 'dialog-enhancer-amount': ('0..16', 'intensità enfasi dialoghi', 'dedotto'),
 'dialog-enhancer-ducking': ('0..16', 'attenuazione del resto durante i dialoghi', 'dedotto'),
 'volume-leveler-amount': ('0..10', 'intensità livellatore', 'dedotto'),
 'volume-leveler-in-target': ('1/16 dB', 'livello di ingresso atteso (-320 = -20 dB)', 'dedotto'),
 'volume-leveler-out-target': ('1/16 dB', 'livello di uscita voluto', 'dedotto'),
 'ieq-amount': ('0..16', 'intensità equalizzatore intelligente', 'dedotto'),
 'ieq-bands-set': ('1/16 dB x 20 bande', 'curva bersaglio IEQ', 'dedotto'),
 'graphic-equalizer-bands': ('1/16 dB x 20 bande', 'guadagni equalizzatore grafico', 'dedotto'),
 'bass-enhancer-boost': ('1/16 dB', 'guadagno bassi', 'dedotto'),
 'bass-enhancer-cutoff-frequency': ('Hz', 'frequenza di taglio bassi', 'dedotto'),
 'bass-enhancer-width': ('1/4 ottava?', 'larghezza del filtro bassi', 'ignoto'),
 'bass-extraction-cutoff-frequency': ('Hz', 'taglio estrazione bassi', 'dedotto'),
 'virtual-bass-src-freqs': ('Hz [min,max]', 'banda sorgente bassi virtuali', 'dedotto'),
 'virtual-bass-mix-freqs': ('Hz [min,max]', 'banda di missaggio armoniche', 'dedotto'),
 'virtual-bass-subgains': ('1/16 dB x 3', 'guadagni armoniche 2a/3a/4a', 'dedotto'),
 'virtual-bass-overall-gain': ('1/16 dB', 'guadagno bassi virtuali', 'dedotto'),
 'virtual-bass-slope-gain': ('?', 'pendenza bassi virtuali', 'ignoto'),
 'regulator-relaxation-amount': ('1/16 dB', 'rilascio del regolatore (96 = 6 dB)', 'dedotto'),
 'regulator-timbre-preservation': ('0..16', 'preservazione del timbro', 'dedotto'),
 'regulator-overdrive': ('1/16 dB', 'sovraccarico ammesso', 'dedotto'),
 'regulator-distortion-slope': ('1/16', 'pendenza distorsione (16 = 1.0)', 'dedotto'),
 'regulator-stress-amount': ('1/16 per canale', 'quantità di stress per canale', 'dedotto'),
 'threshold_high': ('1/16 dB x 20 bande', 'soglia alta del regolatore', 'dedotto'),
 'threshold_low': ('1/16 dB x 20 bande', 'soglia bassa del regolatore', 'dedotto'),
 'isolated_band': ('0/1 x 20 bande', 'banda regolata isolatamente', 'dedotto'),
 'ch_00': ('1/16 dB x 20 bande', 'guadagni per canale (ottimizzatore)', 'dedotto'),
 'peak-level': ('1/16 dB', 'livello di picco', 'dedotto'),
 'mb-compressor-target-power-level': ('1/16 dB', 'livello obiettivo AGC', 'dedotto'),
 'mb-compressor-band0-slow-gain-mix-level': ('Q8 (256 = 1.0)', 'mix guadagno lento banda 0', 'dedotto'),
 'band_group_0': ('?', 'gruppo bande compressore [6 valori]', 'ignoto'),
 'sliding-bass-attack-time': ('ms', 'attacco sliding bass', 'dedotto'),
 'sliding-bass-release-time': ('ms', 'rilascio sliding bass', 'dedotto'),
 'sliding-bass-xo-frequency': ('Hz', 'incrocio sliding bass', 'dedotto'),
 'noise-gate-threshold': ('1/16 dB', 'soglia noise gate (-1440 = -90 dB)', 'dedotto'),
 'mix_matrix': ('Q14 (16384 = 1.0)', 'matrice di missaggio uscita', 'visto: 11583 = 0.707*16384'),
 'band_20_freq': ('Hz', 'centri delle 20 bande', 'visto'),
}
for i in range(1, 10): U['ch_%02d' % i] = U['ch_00']
for i in range(1, 4): U['band_group_%d' % i] = U['band_group_0']
UNIT_ENABLE = ('0/1', 'attivo/spento', 'visto')

def num(s):
    if s is None or s == '': return None
    if not re.fullmatch(r'[-\d.,\s]+', s): return s  # es. coefficienti PEQ in base64 di altri modelli
    v = [float(x) if '.' in x else int(x) for x in s.split(',')]
    return v if len(v) > 1 or ',' in s else v[0]

def load(path):
    root = ET.parse(path).getroot()
    const = {c.tag: {k: num(v) for k, v in c.attrib.items()} for c in root.find('constant')}
    cval = {k: (v.get('target') if 'target' in v else v) for k, v in const.items()}
    head = {e.tag: e.get('value') for e in root if len(e) == 0}
    head.update({e.tag: e.get('value') for e in root.find('setting') if e.tag != 'security-key'})
    eps = {}
    for ep in root.findall('endpoint'):
        cfg = {}
        for e in ep.find('speaker-config'):
            cfg[e.tag if e.tag != 'speaker' else 'speaker_' + e.get('name')] = num(e.get('value')) if e.tag != 'speaker' else \
                {'sbf_eq_enable': num(e.get('sbf_eq_enable')), **{k: num(v) for k, v in e.find('speaker-way').attrib.items()}}
        profs = {}
        for p in ep.findall('profile'):
            par, ref = {}, {}
            def walk(e, pre):
                for k in e:
                    key = pre + '.' + k.tag
                    if len(k): walk(k, key); continue
                    if 'preset' in k.attrib:
                        ref[key] = k.get('preset'); par[key] = cval[k.get('preset')]
                    elif set(k.attrib) <= {'value'}:
                        par[key] = num(k.get('value'))
                    else:
                        par[key] = {a: num(v) for a, v in k.attrib.items()}
            for blk in p: walk(blk, blk.tag.replace('tuning-', ''))
            profs[p.get('type')] = {'n_parametri': len(par), 'parametri': par, 'preset_usati': ref}
        eps[ep.get('type')] = {'attributi': dict(ep.attrib), 'config_altoparlanti': cfg, 'profili': profs}
    # verifica indipendente: foglie (tag autochiusi) per profilo contate sul testo grezzo
    raw = open(path, encoding='utf-8').read()
    for ep_t, blk in re.findall(r'<endpoint type="(\w+)".*?>(.*?)</endpoint>', raw, re.S):
        for pt, body in re.findall(r'<profile type="(\w+)">(.*?)</profile>', blk, re.S):
            n = len(re.findall(r'<[\w-]+[^>]*/>', body))
            assert n == eps[ep_t]['profili'][pt]['n_parametri'], (path, ep_t, pt, n)
    return head, const, eps

def unita(names):
    out = {}
    for n in sorted(names):
        leaf = n.split('.')[-1]
        u = U.get(leaf) or (UNIT_ENABLE if leaf.endswith('-enable') or leaf.endswith('_enable') else None)
        if u: out[leaf] = {'unita': u[0], 'significato': u[1], 'certezza': u[2]}
    return out

if __name__ == '__main__':
    spk, hp, out = sys.argv[1:4]
    res = {'nota': 'valori grezzi come nel file Dolby; unità e significato in "unita" (per nome foglia)', 'file': {}, 'costanti': None, 'endpoint': {}}
    for f in (spk, hp):
        head, const, eps = load(f)
        res['file'][f.split('/')[-1]] = head
        res['costanti'] = res['costanti'] or const
        res['endpoint'].update({k: dict(v, file=f.split('/')[-1]) for k, v in eps.items()})
    names = {k for e in res['endpoint'].values() for p in e['profili'].values() for k in p['parametri']}
    res['unita'] = unita(names)
    json.dump(res, open(out, 'w'), indent=1, ensure_ascii=False)
    chk = json.load(open(out))
    for e, v in chk['endpoint'].items():
        print(e, {p: x['n_parametri'] for p, x in v['profili'].items()})
