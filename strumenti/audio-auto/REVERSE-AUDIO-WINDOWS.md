# Reverse engineering dell'audio di Windows 11 sul Lenovo Yoga Slim 7x (prima passata, 2026-11-16)

Scopo: capire che cosa fa Windows agli altoparlanti di questo portatile, per avvicinare l'audio di Linux.
Metodo: analisi statica dei file del driver (nessuna esecuzione). Ogni affermazione è marcata
**visto** (letto nei file), **dedotto** (interpretazione) o **ignoto**.

## Fonti
- Dolby: `dax3_ext_qc…\AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml` (copia in `audio/windows/`). L'INF lo associa a `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`, che è l'audio di questo PC (**visto**).
- Qualcomm: `qcacsp_idea4001…\acdb_cal.acdb` (copia in `audio/windows/`), formato ACDB AudioReach. Il formato dei blocchi e dei parametri viene dai sorgenti pubblici `Audioreach/audioreach-graphservices` e `audioreach-engine` (**visto**).
- `workspaceFile.qwsp`: cifrato o compresso, non letto (**ignoto**).
- Strumenti usati: `tools/re-audio/*.py` (ripetibili: vedi in fondo).

## 1. Lato Windows (APO Dolby Atmos DAX3), profilo predefinito "dynamic", altoparlanti interni a 2 canali
Valori **visti** nell'XML (unità Dolby: 1/16 dB dove applicabile):
- Equalizzazione fissa: **nessuna** (`audio-optimizer-enable=0`, bande tutte a zero; `graphic-equalizer-enable=0`; `ieq-enable=0`, i bersagli IEQ "detailed/balanced/warm" esistono ma qui non sono attivi).
- Virtualizzatore surround per altoparlanti: attivo (`surround-decoder-enable=1`, angoli altoparlanti 10°, `surround-boost=96` = 6 dB, modalità d'uscita 11 a 2 canali).
- Enfasi dei dialoghi: attiva (`dialog-enhancer-enable=1`, quantità 5).
- Livellatore: `volume-leveler-enable=0` ma `volume-leveler-drc-enable=1`, quantità 5, bersaglio −320 (= −20 dB).
- Regolatore (limitatore multibanda a 20 bande): attivo, soglie alta 0 e bassa −192 (= −12 dB) su tutte le bande, `timbre-preservation=12`, `relaxation-amount=96`, nessuna banda isolata.
- `volmax-boost=96` (= +6 dB), `pregain=0`, `postgain=0`, bassi virtuali e bass enhancer spenti.
- Elaborazione "media intelligence" attiva (pilota virtualizzatore, livellatore, dialoghi).
**Dedotto**: il carattere "immersivo" di Windows viene dal virtualizzatore surround e dall'elaborazione adattiva Dolby, non da un'equalizzazione fissa. Sono algoritmi proprietari: i parametri si leggono, l'algoritmo no.

## 2. Lato DSP Qualcomm (ADSP), dal file ACDB
**Visto**: 31 blocchi (HEAD, GKVT, GKVL, CSLU, CAKT, CDLU, CDDE, CDDO, SCLU, …, SGIT, POOL, …); 180 sottografi, 1210 istanze di moduli, 3486 parametri di calibrazione (211 coppie definizione/dati).
Catena degli altoparlanti (**visto**, ordine dei moduli nei sottografi):
- Sottografo `0xB0000003` (post-elaborazione del dispositivo): GAIN → `0x07001097` → MSIIR ×3 → `0x07001068` → EC_SYNC → MFC → IIR_MBDRC → `0x070010A3` → VOL_CTRL → CHMIXER → SPLITTER.
- Sottografo `0xB0000001` (uscita): SAL (limitatore) → SPLITTER → SPEAKER_PROTECTION → `0x070010E4` → CODEC_DMA_SINK → CHMIXER, con ritorno di tensione e corrente: CODEC_DMA_SOURCE ×3 → SPEAKER_PROTECTION_VI.
Parametri decodificati (**visto**):
- GAIN: variante attiva a 48 kHz = 11571 in Q13 = **+3,0 dB** (la variante di base è disattivata).
- MSIIR-1 (istanza 0x4017): attivo sui canali L, R, LB, RB con un biquad neutro; in una variante pregain +15 dB sul canale LB.
- MSIIR-2 e MSIIR-3 (0x4018, 0x4019): contengono un'equalizzazione a 5 biquad sul canale L, ma il **modulo è disattivato** (`MODULE_ENABLE=0`). Risposta dei 5 biquad (dB a 48 kHz): 40 Hz +4,5 · 80 +9,9 · 150 +14,3 · 300 +10,5 · 600 +8,8 · 1k +10,9 · 2k +3,5 · 3k +0,4 · 4k −1,7 · 6k +6,3 · 8k +7,0 · 12k +2,6 · 16k +0,9 (calcolata da `acdb_decode2.py`). Coefficienti Q30, numeratore con fattore 2.
- IIR_MBDRC (0x4020): attivo, **1 banda**, limitatore modalità 1, ritardo limitatore 262, finestra 2884; due varianti (ritardo DRC 48 e 480). Campi DRC ancora grezzi.
- SAL: limitatore con soglia 93945856 in Q27 = 0,70 (≈ −3,1 dBFS).
- Matrici dei canali: MFC 4→2 e CHMIXER 4→3 e 4→4 (quella d'uscita scambia il secondo e il terzo canale).
- SPEAKER_PROTECTION (0x411A) e SPEAKER_PROTECTION_VI (0x4121): presenti con molti parametri (blocchi da 1520, 2188 e 2084 byte: modello termico e di escursione degli altoparlanti, **dedotto**).
**Ignoto**: il nome e la funzione dei moduli `0x070010A3` (condivide parametri con il cancellatore d'eco SMECNS), `0x07001097`, `0x07001068`, `0x070010E4`, `0x07001019`; il significato esatto delle chiavi di selezione (CKV `0x100000E…`) e quindi quale variante è attiva in ogni situazione.

### 2b. Compressore e limitatore del DSP (IIR_MBDRC, istanza 0x4020), decodifica completa
Struttura del parametro da 128 byte (**visto**, combinando `mbdrc_api.h` con i dati): intestazione (bande, modalità limitatore, ritardo, finestra, numero di configurazioni, ritardo DRC), poi per configurazione: maschera canali, limitatore (36 byte), DRC della banda (56 byte), flag di muto.
Variante attiva per i canali L, R, LB, RB (maschera 0x306), ritardo DRC 480 campioni (10 ms):
- Limitatore: soglia 93945856 (Q27) = 0,70 = **−3,1 dBFS**; guadagno di recupero 256 (Q8) = 1,0; coefficiente di recupero 32440 (Q15) = 0,99; attesa massima 82; soglia rigida uguale.
- DRC: attivo (modo 1), canali collegati, guadagno di recupero 4096 (Q12) = **0 dB**.
- Compressore verso il basso: soglia 10789, pendenza 52428/65536 = 0,80 cioè **rapporto 5:1**, isteresi 18855.
- Compressore verso l'alto: soglia 3877, pendenza 0 (di fatto spento). Espansore verso il basso: soglia 3877, pendenza −102, guadagno minimo −6 dB (Q23).
- **Dedotto** (convenzione Qualcomm: soglie in dB Q7 riferite a circa −96 dB): soglia del compressore ≈ **−12 dBFS**, soglie di espansore e compressore verso l'alto ≈ −66 dBFS.
Variante di base (tutti i canali, ritardo 48): compressore con soglia 9637 (≈ −21 dBFS, **dedotto**) e pendenza 0,95 (20:1).
Confronto con la catena PipeWire del kit (`audio/50-yoga-altoparlanti.conf`): lì il compressore ha soglia −24 dBFS, 3:1, +12 dB di recupero e limitatore a −1,5 dBFS con +6 dB in ingresso. Windows comprime più tardi e più deciso, senza recupero, e limita a −3,1 dBFS: cioè è **più prudente** sui livelli digitali; il volume in più gli viene dalla protezione degli altoparlanti, non da più guadagno nel DSP.

### 2c. Moduli proprietari
`0x070010A3`, `0x07001097`, `0x07001068`, `0x070010E4`, `0x07001019`: nessuna definizione nei sorgenti pubblici (header AudioReach, `sound/soc/qcom/qdsp6/audioreach.h` del kernel, documentazione audioreach.github.io) né nomi vicini agli identificativi nel firmware ADSP (**ignoto**). Nel firmware sono presenti i moduli `capi_audiosphere`, `capi_pbe` (bassi psicoacustici), `capi_virtualizer`, `capi_bassboost` (**visto**): uno di questi potrebbe corrispondere a `0x070010A3` (**dedotto**, non dimostrato).

## 3. Che cosa significa per Linux
- Non c'è un'equalizzazione fissa di Windows da copiare: lato Dolby è a zero e lato DSP l'equalizzatore a 5 bande è spento.
- Riproducibile: guadagno +3 dB, compressore a banda singola + limitatore, limitatore finale a −3 dBFS, instradamento dei canali. La catena PipeWire del kit fa già cose equivalenti (compressore, limitatore, crossover).
- Non riproducibile oggi: virtualizzatore e intelligenza Dolby (proprietari), modulo `0x070010A3` (ignoto), e soprattutto la **protezione degli altoparlanti** con misura di tensione e corrente, che è ciò che permette a Windows di suonare più forte senza rischi. I suoi parametri per questi altoparlanti sono nel file ACDB.
- Strada più promettente per avvicinarsi a Windows in volume: far lavorare su Linux il modulo di protezione del DSP (serve una topologia audio con SPEAKER_PROTECTION e supporto nel kernel) usando i parametri del punto 2. Per la spazialità: un virtualizzatore libero, da tarare a orecchio.

### 3b. Stato della protezione degli altoparlanti su Linux (verificato il 2026-11-16)
- Topologia audio di Linux per questo modello (`X1E80100-LENOVO-Yoga-Slim7x-tplg.bin`, 11 KB): contiene solo decoder PCM, convertitore, controllo volume, logger e uscita verso gli amplificatori. **Nessun modulo SPEAKER_PROTECTION, nessun compressore, nessun limitatore** (**visto**: identificativi dei moduli cercati nel file).
- Anche il sorgente della topologia a monte (`linux-msm/audioreach-topology`, `X1E80100-LENOVO-Yoga-Slim7x.m4`) non contiene la protezione (**visto**).
- Il driver del kernel invece la supporta: `sound/soc/qcom/qdsp6/audioreach.c` gestisce `MODULE_ID_SPEAKER_PROTECTION` e `MODULE_ID_SPEAKER_PROTECTION_VI` (modo operativo, mappa dei canali) (**visto** nel kernel corrente).
- **Dedotto**: per avere il volume di Windows su Linux serve una topologia per questo modello che inserisca la protezione con il ritorno di tensione e corrente, più i parametri degli altoparlanti (quelli dell'ACDB, che il driver oggi non invia), e solo dopo si possono alzare i limiti di guadagno imposti dal kernel. È lavoro di sviluppo da provare sull'hardware, non una configurazione.

## 4. Per continuare (serve il portatile sotto Linux, per misurare con i microfoni)
```
python3 tools/re-audio/acdb_scan.py   audio/windows/acdb_cal.acdb tools/re-audio/ids.txt /tmp/acdb.json   # inventario
python3 tools/re-audio/acdb_spk.py    /tmp/acdb.json tools/re-audio/ids.txt                               # catena altoparlanti
python3 tools/re-audio/acdb_decode2.py audio/windows/acdb_cal.acdb /tmp/acdb.json tools/re-audio/ids.txt  # parametri decodificati
python3 tools/re-audio/acdb_ckv.py    audio/windows/acdb_cal.acdb                                         # varianti e chiavi
```
Da fare: decodificare per intero IIR_MBDRC e i parametri della protezione; capire le chiavi CKV; identificare `0x070010A3`; confrontare con misure la risposta di Windows e di Linux.
