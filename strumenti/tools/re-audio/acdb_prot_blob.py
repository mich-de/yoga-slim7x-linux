#!/usr/bin/env python3
"""Costruisce il file di taratura della protezione altoparlanti per il DSP (ADSP AudioReach).
Ingresso: sp_tag.json e vi_tag.json (tabelle MTLU dell'ACDB di Windows, tag 0x0401000a e
0x0401000b del sottografo 0xB0000001, prodotte con acdb_module_tag_inventory.py del progetto
geocausa/SP11X1e-audio) e i valori R0/T0 del registro di Windows
(HKLM\\SYSTEM\\ControlSet001\\Services\\qcadcm\\State\\SpeakerProtectionInfo\\N, vedi hive_spkr.py).
Uscita: sequenza di frame APM {iid, param_id, size, err=0, dati allineati a 8} nell'ordine di
Windows: taratura di sottografo (sg_cal.json, se presente: SP_RX poi SP_VI), modo normale di SP_RX,
taratura SP_RX, poi R0/T0, modo e modo escursione del VI, taratura SP_VI, infine l'endpoint V/I
(viep_tag.json: 8000 Hz, 32 bit). Il driver Linux manda i frame cosi' come sono, uno per comando.
Uso: acdb_prot_blob.py DIR_JSON uscita.bin R0Q24:T0Q6 x4 [--bits 16] [--calibrazione]
--calibrazione: SP_RX e SP_VI in modo calibrazione (1): il DSP misura R0 con il tono pilota; l'esito si legge
con il parametro 0x080011F8 di SP_VI (stato e R0 per altoparlante). Serve a provare il ritorno V/I."""
import json, struct, sys
d, out = sys.argv[1], sys.argv[2]
r0t0 = [tuple(int(x, 0) for x in a.split(':')) for a in sys.argv[3:] if ':' in a]
bits = int(sys.argv[sys.argv.index('--bits') + 1]) if '--bits' in sys.argv else 16
n = len(r0t0)
modo = 1 if '--calibrazione' in sys.argv else 0
assert n == 4 and all(0x2000000 <= r <= 0x40000000 and -1920 <= t <= 5120 for r, t in r0t0)
def row(name, want):
    for r in json.load(open(f'{d}/{name}'))['rows']:
        if {int(s['key_id'], 0): s['value'] for s in r['selection']} == want:
            return [(int(p['iid'], 0), int(p['param_id'], 0), p['pool_offset']) for p in r['parameters']]
    raise SystemExit(f'riga non trovata in {name}: {want}')
acdb = open(json.load(open(f'{d}/sp_tag.json'))['source'], 'rb').read()
def chunk(name):                       # corpo del chunk ACDB
    o = 12
    while o < len(acdb):
        cc, sz = acdb[o:o+4], struct.unpack_from('<I', acdb, o+4)[0]
        if cc == name: return acdb[o+8:o+8+sz]
        o += 8 + sz
pool = chunk(b'POOL')
def payload(off):                      # oggetto POOL: dimensione + dati
    off = int(off, 0); sz = struct.unpack_from('<I', pool, off)[0]
    return pool[off+4:off+4+sz]
def frame(iid, pid, data):
    return struct.pack('<4I', iid, pid, len(data), 0) + data + b'\0' * (-len(data) % 8)
SP, VI = 0x411A, 0x4121
frames = []
try:                                   # stadio 1: taratura di sottografo, prima di quella con tag
    sg = [(int(r['iid'], 0), int(r['param_id'], 0), r['pool_offset']) for r in json.load(open(f'{d}/sg_cal.json'))['rows']]
    frames += [frame(i, p, payload(o)) for want in (SP, VI) for i, p, o in sg if i == want]
except FileNotFoundError:
    pass
frames.append(frame(SP, 0x080011E9, struct.pack('<I', modo)))          # modo operativo: 0 normale, 1 calibrazione
frames += [frame(i, p, payload(o)) for i, p, o in row('sp_tag.json', {0x0100000f: bits, 0x01000010: n})]
frames.append(frame(VI, 0x080011F5, struct.pack('<I', n) + b''.join(struct.pack('<ihh', r, t, 0) for r, t in r0t0)))
frames.append(frame(VI, 0x080011F4, struct.pack('<3I', n, modo, 0) + struct.pack('<%dI' % n, *[0]*n)))   # modo, R0/T0 tarati
frames.append(frame(VI, 0x080011FF, struct.pack('<I', 0)))
frames += [frame(i, p, payload(o)) for i, p, o in row('vi_tag.json', {0x01000010: n})]
frames += [frame(i, p, payload(o)) for i, p, o in row('viep_tag.json',
           {0x0100000e: 8000, 0x0100000f: 32, 0x01000010: n, 0x01000012: 2, 0x01000022: 1})]
open(out, 'wb').write(b''.join(frames))
for f in frames:
    i, p, s, _ = struct.unpack_from('<4I', f); print('%#06x %#010x %5d' % (i, p, s))
print('frame %d, byte %d' % (len(frames), sum(map(len, frames))))
