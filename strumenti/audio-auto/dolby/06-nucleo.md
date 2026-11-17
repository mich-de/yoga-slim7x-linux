# 06 — Il nucleo di elaborazione del segnale (DAP)

Fase di studio, sola lettura statica dei binari ARM64 in `$D/bin` (pacchetto dax3_swc_aposvc).
Legenda: **visto** = letto nel binario (indirizzo o stringa); **dedotto** = ragionamento su ciò che è visto;
**ignoto** = non determinato. Lettura statica non è esecuzione osservata: dove cito misure dal vivo vengono
dal progetto gemello SP11 (Surface Pro 11), con build dei DLL diversa dalla nostra.

File di lavoro (script e disassemblati parziali): `$D/work/06/`.

## 0. Sintesi

- Il suono non lo elabora una libreria esterna: in ogni DLL è **collegata staticamente** una libreria Dolby
  in C con API "query_memory / init / query_scratch / set_* / process". Non è esportata: i DLL esportano solo
  le 4 funzioni COM (**visto**, `*.hdr.txt`; già notato dal gemello in `docs/findings/2026-08-01-dolby-integration-map.md` §3).
- Tre famiglie di nucleo, riconoscibili dal tipo di stato (nomi RTTI, **visto**):
  - `dap_cpdp_state_s` → DAP "content processing" (DolbyAPOv251, DolbyAPOv2100);
  - `dap_vr_state_s` → DAP con virtualizzatore/cuffie (DolbyAPOVR);
  - `dap_vlldp_state_s` → "VLLDP", elaborazione legata all'altoparlante (DolbyAPOvlldp, vlldp120/130/140/150).
- Sul Yoga sono attivi **DolbyAPOVR (SFX, contenuto)** e **DolbyAPOvlldp150 (MFX, dispositivo)** in serie
  (rapporti 02/05 di questa cartella; ordine VLLDP→VR osservato dal vivo dal gemello,
  `docs/audit/2026-08-05-CANONICAL-DOLBY-PIPELINE.md`).
- Tutto in **virgola mobile a 32 bit**, blocchi interni di **256 campioni a 48 kHz**, 20 bande.

## 1. Versioni e differenze fra i DLL

| DLL | versione nucleo (stringa ASCII, **visto**) | classe wrapper (RTTI/log, **visto**) | stato | PDB |
|---|---|---|---|---|
| DolbyAPOv251.dll | `2.5.1-P2.1` | `Dap2LibWrapperV2_5`, `LibWrapperDap2` | `dap_cpdp_state_s` | `...\DolbyAPOv251\ARM64\Release\DolbyAPOv251.pdb` |
| DolbyAPOv2100.dll | `2.10.0` | `Dap2LibWrapperV2_10` (+ `CDolbyAPOLite`) | `dap_cpdp_state_s` | idem v2100 |
| DolbyAPOVR.dll | nessuna stringa "x.y.z" propria | `LibWrapperVr`, `LibWrapperDap2` | `dap_vr_state_s` | `...\DolbyApoVr\...\DolbyApoVr.pdb` |
| DolbyAPOvlldp.dll | `1.3.1-lite`,`1.4.1-lite`,`1.4.2-lite` | `VlldpLibWrapperV1_0` | `dap_vlldp_state_s` | |
| DolbyAPOvlldp120/130/140 | idem | `VlldpLibWrapperV1_2/1_3/1_4` | idem | |
| DolbyAPOvlldp150.dll | idem + `1.5-lite` (UTF-16) | `VlldpLibWrapperV1_5`, `LibWrapperVlldp`, `CApoBaseVlldp` | idem | |

Versione file di tutti: `3.30812.891.0` (**visto**, VS_VERSION_INFO). Le stringhe "x.y-lite" in ogni vlldp sono
probabilmente una tabella di compatibilità di `CPPAPIHelper` (codice condiviso con Dax3DapControl) (**dedotto**).

Insiemi di funzioni (dai nomi di parametro presenti, **visto** nelle tabelle `| nome | min | max |` in UTF-16):

- **v251 (DAP 2.5)**: 39 parametri scalari + vettori (vedi §2): livellatore di volume (volume-leveler),
  modellatore di volume, enfasi dialoghi, IEQ, equalizzatore grafico, ottimizzatore audio, regolatore,
  bass enhancer, estrazione bassi, decoder surround, virtualizzatore (angoli front/height/surround),
  volmax, pregain/postgain/system-gain, guida "mi-*" (media intelligence), height filter, output-mode con
  mix_matrix, audio-sharing, spatial-enable.
- **v2100 (DAP 2.10)** = v251 + `bass-extraction-LFE-gain`, `custom-woofer-channel-index`,
  `rear-height-filter-mode`, `surround-decoder-center-spreading-enable`, angoli
  `virtualizer-rear-surround/rear-height`, `virtualizer-start-band-set`, `woofer-regulator-*` (**visto**, diff
  delle tabelle). Pensato per configurazioni con woofer/canali posteriori.
- **VR** = v251 + `volume-leveler-drc-enable`, `volume-leveler-compressor-enable`, `eyes-tracking-enable`,
  `mi-virtualizer-steering-enable` (**visto**) e un modulo cuffie Dolby Atmos for Headphones:
  `dolby::spatial_sound::dahp::configure_init_time/configure_real_time`, "SS-C Configurator",
  `LibWrapperVr::GetDefaultHeadphoneTuningResource`, buffer "phrtf" (**visto**, stringhe). Setter vettoriali
  con nome: `dap_vr_audio_optimizer_bands_set`, `dap_vr_graphic_equalizer_bands_set`, `dap_vr_ieq_bands_set`,
  `dap_vr_output_mode_set`, `dap_vr_process_optimizer_bands_set`, `dap_vr_regulator_tuning_set` (**visto**).
- **VLLDP** (device processing, "lite"): niente virtualizzatore/dialoghi/IEQ; contiene ottimizzatore audio
  (20 bande per canale), regolatore (soglie per banda, stress, slope, overdrive, timbre), compressore
  multibanda (fino a 4 gruppi di bande, AGC, slow gain), "sliding bass", noise gate, peak limiter
  (`peak_level`), ultrasonic pilot, guadagni/mute per canale, filtri (`vlldp-filter-config`) e visualizzatore.
  Il numero di setter cresce con la versione: v1.0 e v1.2: 7, v1.3: 8, v1.4: 15, v1.5: 23 (**visto**, conteggio
  stringhe `dap_vlldp_*_set`). Anche la firma cambia: `dap_vlldp_query_memory(%d)` in v1.0, 3 argomenti in v1.2,
  4 da v1.3 in poi; `dap_vlldp_init` 3 → 4 → 5 argomenti (**visto**, stringhe di log).

## 2. Tabella dei parametri

### 2.1 Come arrivano i parametri (**visto**)

I wrapper costruiscono all'avvio (inizializzatori statici) una tabella di voci
{PROPERTYKEY, gestore generico, setter della libreria, stringa di log}; il setter è un
`std::function<void(dap_xxx_state_s*, int)>` (tipi RTTI `_Func_impl_no_alloc<P6AXPEAUdap_vlldp_state_s@@H@Z...>`).
Il valore viene letto dal property store dell'endpoint e passato al setter.

- DAP (v251, VR): PROPERTYKEY `{f112024a-fe30-42a8-80ab-8dd825a06f78},pid`.
  Tabella in v251 `0x180004e40`, in VR `0x180005340` (+ `0x180006e04` per i 4 parametri solo VR).
- VLLDP150: PROPERTYKEY `{5510c7ab-dfc2-40d0-a98b-5f77f697005e},pid`.
  Tabelle in `0x180005060` e `0x1800062e0`; vettori in `VlldpLibWrapperV1_5::UpdatePropertyKeys` `0x180015420`
  e `LibWrapperVlldp::UpdatePropertyKeys` `0x1800322f0`.

### 2.2 DAP (pid, setter in v251 / in VR) — **visto**

| parametro | pid | v251 | VR |
|---|---:|---|---|
| system-gain | 0 | 0x1800235a0 | 0x18003fe90 |
| calibration-boost | 1 | 0x1800232d0 | 0x18003fc90 |
| volmax-boost | 2 | 0x180023660 | 0x18003ff40 |
| pregain | 3 | 0x180023450 | 0x18003fde0 |
| postgain | 4 | 0x180023390 | 0x18003fd30 |
| volume-modeler-calibration | 5 | 0x1800238a0 | 0x180040120 |
| volume-leveler-out-target | 6 | 0x1800237e0 | 0x180040080 |
| volume-leveler-in-target | 7 | 0x180023720 | 0x18003ffe0 |
| volume-modeler-enable | 8 | 0x180024130 | 0x180040b00 |
| ieq-enable | 9 | 0x180023ef0 | 0x1800408d0 |
| volume-leveler-enable | 10 | 0x1800240c0 | 0x180040a90 |
| volume-leveler-amount | 11 | 0x180024050 | 0x180040940 |
| ieq-amount | 12 | 0x180023d90 | 0x180040770 |
| bass-enhancer-enable / -boost / -cutoff-frequency / -width | 14/15/16/17 | 0x18001afa0 / aea0 / af20 / b010 | 0x180036710 / 6610 / 6690 / 6780 |
| audio-optimizer-enable | 19 | 0x18001ae20 | 0x180036590 |
| graphic-equalizer-enable | 20 | 0x18001b400 | 0x180036cc0 |
| regulator-enable | 23 | 0x18001cbb0 | 0x1800388f0 |
| regulator-speaker-dist-enable | 24 | 0x18001cd20 | 0x180038a60 |
| regulator-relaxation-amount | 25 | 0x18001cca0 | 0x1800389e0 |
| regulator-timbre-preservation | 26 | 0x18001cd90 | 0x180038ad0 |
| regulator-overdrive | 27 | 0x18001cc20 | 0x180038960 |
| mi-ieq / mi-dv-leveler / mi-dialog-enhancer / mi-surround-compressor steering | 31/32/33/34 | 0x180023c50 / bf0 / b90 / cb0 | 0x1800405a0 / 540 / 4e0 / 600 |
| surround-decoder-enable | 35 | 0x18001d100 | 0x180038ed0 |
| surround-boost | 36 | 0x18001d070 | 0x180038e40 |
| dialog-enhancer-ducking / -amount / -enable | 37/38/39 | 0x18001b200 / b180 / b2b0 | 0x1800369f0 / 6980 / 6a80 |
| mi-virtualizer-steering-enable | 49 | (non in tabella) | 0x180040480 |
| bass-extraction-enable / -cutoff-frequency | 50/51 | 0x18001b110 / b090 | 0x180036890 / 6800 |
| height-filter-mode | 52 | 0x18001b470 | 0x180036d30 |
| virtualizer-front/height/surround-speaker-angle-set | 56/57/58 | 0x1800239b0 / 3a30 / 3ab0 | 0x180040290 / 0310 / 0390 |
| volume-leveler-drc-enable | 76 | — | 0x180040a20 |
| eyes-tracking-enable | 77 | — | 0x180036b70 |
| volume-leveler-compressor-enable | 78 | — | 0x1800409b0 |

Vettori (in `LibWrapperDap2::UpdatePropertyKeys`, v251 `0x1800694e0`): ieq-bands pid 13,
audio-optimizer-bands 18, graphic-equalizer-bands 21, regulator-tuning 22 (**dedotto** dall'ordine chiave→log);
pid 47, 55, 59 sono speaker-virtualizer-enable / audio-sharing-* (**dedotto**, abbinamento esatto ignoto).
Intervalli (min/max interi, **visto**): es. pregain/postgain/system-gain −2080..480, volume-leveler-amount 0..10,
in/out-target −640..0, ieq/geq bande 1..20 e frequenze 20..20000, geq gains ±576, ieq targets ±480,
regulator-tuning low/high −2080..0, output-mode processing_mode 0..11 e num_output_channels 0..10.
Le unità sembrano 1/16 dB (−2080 = −130 dB; −640 = −40 dB) (**dedotto**).

`output-mode` (processing_mode ≤ 11, num_output_channels ≤ 10, mix_matrix ≤ 0x4000) è applicato da
v251 `0x18001beb0` (stesso ruolo di `dap_vr_output_mode_set`) (**visto** i confronti `cmp w19,#0xb`, `cmp w8,#0x4,lsl #12`).

### 2.3 VLLDP150 (pid → setter) — **visto**

| parametro | pid | setter |
|---|---:|---|
| vlldp-max-num-channels / max-num-operations (init, non setter) | 1 / 2 | 0x180015200 / 0x180015260 (gestori del wrapper) |
| system_gain | 3 | 0x18001d490 |
| postgain | 4 | 0x18001b4b0 |
| filter-config (vettore) | 5 | 0x180019fc0 |
| audio_optimizer_enable | 6 | 0x180019c20 |
| audio-optimizer bands / gains (vettori, wrapper base) | 7, 9 | via `0x1800322f0` (**dedotto**) |
| regulator-tuning (vettore) | 8 | via `0x1800322f0` (**dedotto**) |
| regulator_overdrive | 10 | 0x18001c850 |
| regulator_timbre_preservation | 11 | 0x18001cb50 |
| regulator_speaker_distortion_enable | 13 | 0x18001c8b0 |
| peak_level | 14 | 0x18001b440 |
| target_power_level | 15 | 0x18001d4f0 |
| mb_compressor_enable | 16 | 0x1800152b0 (gestore wrapper) |
| mb-compressor-tuning (vettore, gruppi) | 17 | 0x18001b110 |
| mb_compressor_channel_deviation / agc_enable / slow_gain_enable / bgroup0_slow_gain_mix_level | 18/19/20/21 | 0x18001aed0 / ae00 / af90 / ae60 |
| regulator stress amount (vettore per canale) | 22 | 0x18001c908 |
| regulator_distortion_slope | 23 | 0x18001c6f0 |
| ultrasonic_pilot_enable | 24 | 0x18001d560 |
| sliding_bass enable / band_boundary / attack / release / max_level / min_level | 25..30 | 0x18001d150 / d0e0 / d070 / d380 / d2a0 / d310 |
| sliding-bass-gain-curve (vettore) | 31 | 0x18001d1a8 |
| channel-gain / channel-mute (vettori) | 32 / 33 | 0x180019dd0 / 0x180019e60 |
| noise_gate_enable / threshold | 34 / 35 | 0x18001b350 / 0x18001b3c0 |

### 2.4 Confronto con l'XML di taratura del Yoga

`AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml`: endpoint `internal_speaker`, `fs="48000"`, 2 canali;
per ogni profilo un blocco `<tuning-cp>` (va al DAP/VR) e un blocco `<tuning-vlldp>` (va al VLLDP150).

- **Corrispondono 1:1** (nome XML = nome parametro DAP): tutti i parametri scalari della tabella §2.2 tranne gli
  angoli: l'XML usa `virtualizer-*-speaker-angle`, l'APO `virtualizer-*-speaker-angle-set` (**visto**).
- `<tuning-vlldp>` ↔ setter VLLDP: `max_num_channels`=2, `max_num_operations`=0 (vanno a init),
  `audio-optimizer-bands` ch_00..ch_07 (20 valori), `mb-compressor-*`, `peak-level`, `postgain`,
  `regulator-stress-amount` (8 valori, uno per canale), `regulator-distortion-slope`, `regulator-tuning`
  (`threshold_high`/`threshold_low`/`isolated_band`, 20 bande), `sliding-bass-*`, `system-gain`, `noise-gate-*`
  (**visto** nell'XML; corrispondenza con i nomi `dap_vlldp_*_set` **visto**).
- **Presenti nell'XML ma in nessuno dei 4 nuclei né in DAX3API/Dax3DapControl**: `virtual-bass-*`
  (mode, src/mix freqs, subgains, slope/overall gain), `sliding-bass-xo-frequency`, `sliding-bass-max-gain`,
  `speaker-peq-filters`, `output_ports`, `mode`. `speaker-peq-enable`, `process-optimizer-*`, `ieq-bands-set`,
  `mi_process_disable`, `virtual_bass_process_enable` compaiono solo in DAX3API (**visto**, ricerca nelle stringhe).
  Quindi questi campi o vengono ignorati da questa versione o sono tradotti da DAX3API in altri parametri
  (**ignoto** quale dei due).
- `volume-leveler-drc-enable` è nell'XML e solo in VR: conferma che il `<tuning-cp>` è scritto per il VR (**dedotto**).

## 3. Funzioni principali del nucleo

Convenzione ARM64: argomenti in x0..x7 / w0..w7. "wrap" = oggetto LibWrapper; `[[wrap+8]]` = primo campo
della descrizione del formato (frequenza di campionamento, **dedotto**).

### 3.1 VLLDP150 (DolbyAPOvlldp150.dll)

Chiamate da `VlldpLibWrapperV1_5::InitLibrary` = `0x180014cb0` (slot 4 della vtable `0x18017f3c0`; **visto**,
log "VlldpLibWrapperV1_5::InitLibrary").

| funzione | indirizzo | argomenti (dedotti) | chiamata da |
|---|---|---|---|
| dap_vlldp_query_memory | `0x18001c598` (116 B) | (blocco=[wrap+0x3c]=256, fs=[[wrap+8]], max_canali=[wrap+0xa8], max_operazioni=[wrap+0x160]) → byte | InitLibrary `0x180014dc8` |
| allocazione | `0x180025918` | (heap, allineamento 4, dimensione) | InitLibrary |
| dap_vlldp_init | `0x18001a2f0` (2476 B) | (blocco, fs, max_canali, max_operazioni, memoria) → stato; scrive stato+8=blocco, +12=fs, +16=canali | InitLibrary `0x180014f18`; stato salvato in wrap+0x158 |
| dap_vlldp_query_scratch | `0x18001c658` (100 B) | (blocco, fs, canali) → byte; per canale `blocco*4+0x27` (float) | InitLibrary `0x180014f90`; scratch in wrap+0x30 |
| setter `dap_vlldp_*_set` | §2.3 | (stato, valore int) | tabelle §2.1 e UpdatePropertyKeys |
| dap_vlldp_process | `0x18001dae8` (4084 B, 17 funzioni chiamate) | (stato, buffer_in, buffer_out, scratch) | metodo in RT_CODE `0x1800fd000` (slot 21): `b 0x18001dae8` con x0=[wrap+0x158], x3=[wrap+0x30] |
| conversione ingresso / uscita | `0x18001eba8` / `0x18001f8a8` | descrittore buffer {nch@0, ?@4, ppdata@8, tipo@16, …@24}; tipo dati 3..8 accettati, interno tipo 3 | process |
| getter stato | `0x180014c80` | ritorna [wrap+0x158] | slot 2 |
| altro metodo RT | `0x1800fd030` → `0x18001d5b8` (532 B) | (stato, wrap+0x58) | slot 27; ruolo **ignoto** (probabile lettura del visualizzatore) |

Interruttore elaborazione: in process `ldr w9,[x23,#3180]` (stato+0xC6C); se 0 copia/azzera e salta l'elaborazione
(**visto** `0x18001db38`). Il gemello lo chiama "child1+0xc6c — 0 = bypass, 1 = live" e lo collega a
`DisableSysFx` (`2026-08-01-dolby-integration-map.md` §5). La nostra `0x18001dae8` corrisponde alla
`FUN_18001f7a8` del gemello (stesso ruolo, "17 callees"; build diversa).

### 3.2 DAP v251 (DolbyAPOv251.dll)

`Dap2LibWrapperV2_5::InitLibrary` = `0x180017120` (**visto**, stringhe di log).

| funzione | indirizzo | argomenti (dedotti) |
|---|---|---|
| dap_cpdp_query_memory | `0x18001c630` (576 B) | (config* = wrap+0x108; config[0]=fs, config+36/+40 = canali/oggetti) → byte |
| dap_cpdp_init | `0x18001b4d8` (1856 B) | (config*, memoria) → stato in wrap+0x138 |
| dap_cpdp_query_scratch | `0x18001c960` (448 B) | (config*) → scratch in wrap+0x30 |
| output_mode_set | `0x18001beb0` (436 B) | (stato, processing_mode ≤11, nb_out ≤10, mix_matrix) |
| prepare (ingresso) | `0x18001c088` | (stato, 1, buffer_in, 0, 0, 0, 0, 0) → n. campioni |
| dap_cpdp_process | `0x1800205c8` (2996 B) | (stato, buffer_out, scratch, &risultato) |

Chiamante dell'elaborazione: metodo RT_CODE `0x180101000` (controlla che prepare restituisca il blocco atteso
da `0x180101d30`, poi chiama process). `LibWrapperDap2::ProcessAudioBlock` = `0x180101e1c` (**visto**, log).

### 3.3 DAP v2100 e VR (stessa struttura, **visto** posizioni; ruoli **dedotti** dall'analogia con v251)

| | v2100 | VR |
|---|---|---|
| InitLibrary | `0x18001ae70` | `0x180031e70` (LibWrapperVr) |
| query_memory | `0x180021360` | `0x180038178` |
| init (stato in) | `0x1800205a8` (wrap+0x1d0) | `0x180036d98` (wrap+0x130) |
| query_scratch | `0x180021730` | `0x1800385d8` |
| prepare | `0x180020f38` | `0x180037d20` |
| process | `0x1800265a0` (2748 B) | `0x18003e068` (464 B, smistatore) |
| metodo RT chiamante | `0x180139000` | `0x1801a0000` |
| ProcessAudioBlock | `0x180139e0c` | `0x1801a0e2c` |

## 4. Formato di lavoro

- **Virgola mobile 32 bit** (**visto**): nelle zone del nucleo istruzioni `fmul/fadd/fmla` su `s`/`v.4s`:
  VLLDP ~616, v251 ~2670, VR ~7345; nessuna aritmetica Q31 nel VLLDP. Buffer per canale `blocco*4` byte.
- **VLLDP150 frequenze e blocco** (**visto**, `0x180020ab8` e tabella del wrapper `0x180004e70`):
  44,1/48 kHz → blocco 256; 88,2/96 kHz → 512; 176,4/192 kHz → 768. Altre frequenze: tabella NULL (rifiutate,
  "Unsupported sample rate: [%d]"). Terzo campo della tabella: 176 / 352 / 704 = ritardo in campioni
  (**dedotto**: 176 a 48 kHz = 3,67 ms; il gemello osserva dal vivo wrapper+0x38=176 e +0x3C=256,
  `2026-08-04-DOLBY-LIVE-KDNET-HOT-PATH.md` righe ~770-790). L'APO accumula i blocchi host (es. 480) in blocchi da 256 (gemello, stesso file).
- **Canali VLLDP**: max_num_channels dall'XML = 2; il log "Input channels[%d] and output channels[%d] shall never
  greater than max channel number[%d]" (**visto**); ingresso = uscita (**dedotto**). Valori per canale fino a 8 (ch_00..ch_07).
- **DAP (cpdp/vr) frequenze** (**visto**, tabelle per frequenza `{fs, fs_interna, campioni, bande}`):
  v251 `0x180024728`: 32000→{32000,256,19}, 44100→{44100,256,20}, 48000→{48000,256,20}, 96000→{48000,512,20},
  192000→{48000,1024,20}. VR `0x1800421a0`: come sopra più 88200→{44100,512,20}.
  Quindi 96/192 kHz vengono elaborati internamente a 48 kHz (**dedotto** dal secondo campo).
  Il "20" coincide con il massimo di bande di ieq/geq/ottimizzatore/regolatore (**dedotto**: banco di filtri a
  20 bande percettive; 19 a 32 kHz). Al banco di analisi interno serve `campioni/4` = 64 (v251 `0x18001c670`
  `lsr w20,w8,#2`), compatibile con un banco QMF a 64 sottobande × 4 intervalli (**dedotto**, non verificato).
- **Canali DAP**: uscita fino a 10 (`output-mode:num_output_channels` 0..10), audio-sharing 2..8, log
  "Intermediate channels = %d, Output channels = %d" (**visto**). Ingresso massimo **ignoto** (probabile 7.1).
- **Ritardo DAP/VR**: loggato come "Latency: %d" (wrap+56 in v251) ma il valore non è ricavabile staticamente
  (**ignoto**). Il gemello misura ~689 campioni (14,35 ms) per la catena completa VLLDP+VR
  (`2026-08-04-DOLBY-NATIVE-CHAIN-PROGRESS.md` r. 404, loro hardware).

## 5. Dati costanti notevoli (posizione e dimensione, senza contenuto)

- **Tabelle per frequenza (configurazione del nucleo)**: VLLDP150 `0x180110120` (256/48k), `0x1801102e0`
  (256/44,1k), `0x18010cf70`, `0x18010c170`, `0x18010c750`, `0x18010d830` (altre); v251 `0x18010ef50`,
  `0x180114a30`, `0x18010de20`, `0x18010dec0`, `0x18010df60`, ciascuna con 6-7 puntatori a tabelle di
  coefficienti (es. v251 48k → `0x180118a80`, `0x18011d0e0`, `0x180114b00`…); VR `0x1801ad650`…`0x1801aeed0`.
- **Zone di float contigui in .rdata** (euristica: sequenze ≥512 B di float plausibili, `work/06/floatruns.py`):
  VLLDP150 ~178 KB su 457 KB di .rdata; v251 ~144 KB; v2100 ~189 KB; VR ~245 KB. Le più grandi:
  - 24 588 B identici di dimensione in VLLDP150 `0x180156474`, v2100 `0x1801afbb4`, VR `0x18024cbf4`:
    referenziati solo da codice in fondo a .text (`0x1800e5xxx`) → quasi certamente tabelle della libreria
    matematica di sistema, non Dolby (**dedotto**).
  - v251 `0x1801422b0` (23 680 B, usata da `0x180051b68`…), uguale dimensione in VR `0x1802114c0`; v251
    `0x1801649e8` (22 032 B) uguale a vlldp v1.0 `0x1800f8228`: candidati per prototipi del banco di filtri/finestre (**dedotto**).
  - VR `0x1801b6ab4` (22 408 B), `0x18024872c` (16 436 B): solo nel VR, candidati per il virtualizzatore (**ignoto**).
- **Risorse comuni** (identiche in tutti i DLL, stesso SHA-256): RCDATA 201 (123 684 B) e 202 (123 678 B),
  testo base64 che decodifica con firma "NOSJ"; tipo 255/254 (17 260 B, JSON con base64). Usate da
  `LibWrapperVr::GetDefaultHeadphoneTuningResource` per la taratura cuffie predefinita (**dedotto**: nome della
  funzione + "Deserialization of headphone coefficients failed").
- La taratura altoparlante del Yoga **non** è nei DLL: arriva dall'XML via DAX3API e property store (§2).

## 6. Ignoti principali

1. Valore del ritardo del VR e significato preciso di `prepare` (n. buffer, metadati).
2. Abbinamento esatto dei pid vettoriali DAP 47/55/59 e VLLDP 7/8/9; dove finiscono `virtual-bass-*`,
   `speaker-peq-*`, `sliding-bass-xo-frequency` dell'XML.
3. Canali d'ingresso massimi del DAP e significato dei tipi dati 3..8 nel descrittore buffer.
4. Ruolo di `0x18001d5b8` (VLLDP) e delle grandi tabelle solo-VR.

## 7. Passo successivo consigliato

Per l'interoperabilità basta la superficie trovata: per ciascun nucleo attivo (VLLDP150 e VR) la sequenza
query_memory → init → setter (dai valori dell'XML, §2.4) → output_mode_set → per ogni blocco da 256 campioni
float a 48 kHz: prepare/process. Il passo successivo utile è **ricostruire per il VR il layout del descrittore
buffer e degli argomenti di `prepare` (`0x180037d20`) e di `0x18003e068`**, e verificare la traduzione
XML→property store che fa DAX3API (rapporti 04/07), così da sapere esattamente quali valori del Yoga arrivano a
ciascun setter. Il gemello (`dolby-port/sp11_vlldp_pe_loader.h`, `sp11_dolby_windows_chain_*`) mostra che il
caricamento dei DLL ARM64 su Linux e la chiamata diretta di queste funzioni sono già praticabili.
