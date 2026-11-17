# Audio Yoga, piano 1: motore a file (fasi 1 e 2 del progetto)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un programma a riga di comando che su Fedora ARM64 elabora un file WAV con il codice originale dei due DLL Dolby del portatile, con i parametri di un profilo della taratura.

**Architecture:** i DLL vengono mappati in memoria così come sono (nessuna modifica ai file) e si chiamano per indirizzo le funzioni della libreria Dolby che contengono: creazione, impostazione dei parametri, elaborazione di blocchi da 256 campioni. Prima il solo DLL dell'altoparlante (`DolbyAPOvlldp150.dll`), poi la catena completa con `DolbyAPOVR.dll`. Le prove misurano l'uscita contro i valori della taratura.

**Tech Stack:** C (gcc, aarch64 Linux), Python 3 con numpy per le prove (`python3 -m unittest`).

**Spec:** `PROGETTO.md` (stessa cartella). Riferimenti: `06-nucleo.md` (indirizzi e parametri), `07-taratura.md` e `taratura-yoga.json`, `08-lavoro-pubblico.md`; codice del progetto gemello `geocausa/SP11X1e-audio`, cartella `dolby-port/` (BSD-2: citare la fonte nei file derivati).

## Global Constraints
- I file Dolby non si modificano e non entrano nel repository: il programma li riceve come percorso e li accetta solo se l'impronta SHA-256 è in `dati/sha256-dll-yoga.txt` (versione 3.30812.891.0).
- Nessun aggiramento di controlli: se una verifica di autenticità impedisse l'elaborazione, ci si ferma e si avvisa il proprietario.
- Solo 48 kHz, 2 canali, virgola mobile a 32 bit, blocchi da 256 campioni.
- Nessun suono in questo piano: solo file. Nessuna modifica a PipeWire, volumi, moduli del kernel.
- Niente commit né push senza conferma del proprietario; a ogni compito chiuso si aggiorna `HANDOFF.md` punto 22.
- Sorgenti in `repo/strumenti/audio/dolby/`; messaggi e commenti in italiano; nome del programma `yogadolby`.

## Review Focus
1. DLL di un'altra versione (impronta diversa): il programma rifiuta con un messaggio chiaro e non esegue nulla.
2. Ingresso che non è 48 kHz stereo: rifiuto con messaggio, nessun ricampionamento.
3. Lunghezza non multipla di 256: l'uscita ha la stessa lunghezza dell'ingresso, senza perdere la coda.
4. Campioni non validi in ingresso (NaN, infinito): l'uscita resta finita e lo stato del motore non resta avvelenato.
5. Due esecuzioni sullo stesso ingresso danno uscite identiche byte per byte.

---

## Struttura dei file
| File | Responsabilità |
|---|---|
| `audio/dolby/pe.h` | mappa un DLL in memoria, applica le rilocazioni, verifica l'impronta; chiamata a una funzione del DLL con il registro x18 puntato a un blocco fittizio (serve alle funzioni che controllano lo stack) |
| `audio/dolby/indirizzi.h` | indirizzi delle funzioni dei due DLL per la versione 3.30812.891.0, con la fonte di ciascuno |
| `audio/dolby/vlldp.c`, `vlldp.h` | libreria dell'altoparlante: apri, imposta parametro, elabora blocco, chiudi |
| `audio/dolby/vr.c`, `vr.h` | libreria dei contenuti (fase 2) |
| `audio/dolby/yogadolby.c` | riga di comando: legge il profilo da `taratura-yoga.json`, concatena VR e VLLDP, legge e scrive WAV |
| `audio/dolby/Makefile` | `make` produce `yogadolby` e i programmi di prova |
| `audio/dolby/prove/test_*.py` | prove con numpy: risposta in frequenza, ripetibilità, casi del Review Focus |

## Task 1: il codice originale gira (caricatore e prima chiamata)
**Files:** Create `audio/dolby/pe.h`, `audio/dolby/indirizzi.h`, `audio/dolby/prova1.c`, `audio/dolby/Makefile`.
**Interfaces — Produces:**
- `int pe_carica(pe_t *img, const char *percorso, const char *elenco_impronte)` → 0 se mappato e impronta ammessa; `void *pe_ind(const pe_t *img, uint64_t va)`; `void pe_scarica(pe_t *img)`.
- `uint64_t win_chiama(void *fn, uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4)`: chiama `fn` con x18 = blocco fittizio (campo a +0x10 azzerato).
- `indirizzi.h`: `VLLDP_QUERY_MEMORY 0x18001c598`, `VLLDP_INIT 0x18001a2f0`, `VLLDP_QUERY_SCRATCH 0x18001c658`, `VLLDP_PROCESS 0x18001dae8`, `VLLDP_BYPASS_OFF 0xC6C`.

- [ ] Prova (in `prova1.c`): carica `DolbyAPOvlldp150.dll`; `query_memory(256, 48000, 2, 0)` deve dare un numero fra 4 KiB e 64 MiB; `query_scratch(256, 48000, 2)` deve dare almeno `2 * (256 * 4 + 0x27)`; con un file di impronta diversa `pe_carica` deve fallire senza mappare.
- [ ] Eseguire e vedere che fallisce (manca il codice), poi scrivere `pe.h` adattando `sp11_vlldp_pe_loader.h` del gemello (mappatura e rilocazioni DIR64) e la chiamata con x18.
- [ ] Eseguire: `make prova1 && ./prova1 <cartella dei DLL>` → stampa le due dimensioni e `OK`.

## Task 2: la libreria dell'altoparlante elabora blocchi
**Files:** Create `audio/dolby/vlldp.c`, `vlldp.h`, `prove/test_vlldp_base.py`; Modify `Makefile`.
**Interfaces — Consumes:** Task 1. **Produces:**
- `vlldp_t *vlldp_apri(pe_t *img)` (48 kHz, 2 canali, blocco 256); `void vlldp_elabora(vlldp_t *v, float *const in[2], float *const out[2])`; `int vlldp_imposta(vlldp_t *v, int pid, const int32_t *valori, int n)`; `void vlldp_chiudi(vlldp_t *v)`.
- Descrittore dei buffer come nel rapporto `06` §3.1 (`nch` a 0, puntatori ai canali a 8, tipo a 16); il valore del tipo per i float e l'eventuale preparazione delle tabelle interne si ricavano da `sp11_vlldp_*_ladspa.c` del gemello e si annotano in `indirizzi.h`.

- [ ] Prove: 1 s di silenzio → uscita tutta finita e in modulo sotto 1e-4; un impulso → uscita non nulla; due esecuzioni → uscite identiche byte per byte; ingresso con NaN → uscita finita (il chiamante sostituisce i non validi con 0 prima di elaborare).
- [ ] Eseguire (fallisce), implementare, rieseguire: `python3 -m unittest prove/test_vlldp_base.py` → tutte passate.

## Task 3: i parametri del profilo arrivano all'altoparlante (chiude la fase 1)
**Files:** Modify `vlldp.c`; Create `audio/dolby/profilo.c`, `profilo.h`, `prove/test_vlldp_curva.py`.
**Interfaces — Produces:** `int profilo_applica_vlldp(vlldp_t *v, const char *json, const char *profilo)`: applica tutti i parametri della sezione `tuning-vlldp` con i `pid` della tabella `06` §2.3 (scalari con il setter diretto; vettori `audio-optimizer-bands`, `regulator-tuning`, `mb-compressor-tuning`, `regulator-stress-amount`, `sliding-bass-gain-curve` con la via usata dal DLL, da ricavare leggendo il gestore del wrapper e il codice del gemello).
- [ ] Prova: con il profilo `music`, compressore multibanda e regolatore disattivati dai loro parametri, un segnale di toni a −40 dBFS sulle 20 frequenze di banda esce con guadagni uguali alla curva `audio-optimizer-bands` del canale (in 1/16 dB) entro 0,5 dB; con l'ottimizzatore spento esce entro 0,1 dB da 0.
- [ ] Prova: a parità di tutto, un tono a 200 Hz a −3 dBFS con il regolatore acceso esce più basso che con il regolatore spento (soglie del profilo sotto 700 Hz).
- [ ] Eseguire (fallisce), implementare, rieseguire → passate. Aggiornare `HANDOFF.md`.

## Task 4: la libreria dei contenuti (fase 2)
**Files:** Create `audio/dolby/vr.c`, `vr.h`, `prove/test_vr.py`; Modify `indirizzi.h`, `profilo.c`.
**Interfaces — Produces:** `vr_t *vr_apri(pe_t *img)`; `vr_elabora`, `vr_imposta`, `vr_chiudi` con le stesse forme di `vlldp_*`; `int profilo_applica_vr(vr_t *, const char *json, const char *profilo)` con i `pid` della tabella `06` §2.2. Indirizzi di partenza (ruoli dedotti, da confermare): init `0x180036d98`, prepare `0x180037d20`, process `0x18003e068`.
- [ ] Prove: profilo `off` → uscita uguale all'ingresso entro 0,1 dB a −40 dBFS; `volmax-boost` 96 con il resto spento → +6 dB entro 0,5 dB a −40 dBFS; una banda dell'equalizzatore grafico a +96 → picco di +6 dB entro 1 dB su quella banda e meno di 1 dB due bande più in là; i casi di ripetibilità e NaN del Task 2.
- [ ] Eseguire (fallisce), implementare, rieseguire → passate.

## Task 5: `yogadolby` e i dieci profili
**Files:** Create `audio/dolby/yogadolby.c`, `prove/test_cli.py`; Modify `Makefile`.
**Interfaces — Produces:** `yogadolby --dll CARTELLA --taratura FILE.json --profilo NOME ingresso.wav uscita.wav`; codice d'uscita 0, 2 (DLL rifiutato), 3 (formato non ammesso), 4 (profilo sconosciuto).
- [ ] Prove: i 10 profili elaborano 5 s di rumore rosa a −20 dBFS senza valori non validi; `music` e `movie` danno uscite diverse; lunghezza d'uscita uguale all'ingresso anche con 1000 campioni; WAV a 44,1 kHz o mono → codice 3; DLL con un byte cambiato (copia in una cartella temporanea) → codice 2; due esecuzioni → file identici.
- [ ] Eseguire (fallisce), implementare, rieseguire → passate. Misurare e annotare il ritardo della catena (campioni) per il piano successivo. Aggiornare `HANDOFF.md`.

## Piani successivi (da scrivere dopo questo, con i dati misurati qui)
2. Tempo reale: plugin per PipeWire con passaggio diretto di riserva, servizio separato.
3. App e servizio utente. 4. Inserimento nel kit.
