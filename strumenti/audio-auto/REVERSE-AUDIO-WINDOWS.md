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

## 5. Seconda passata (2026-11-16 sera, da Windows 11 acceso, skill leanrea)
Metodo: registro di Windows in sola lettura, file del DriverStore, firmware ADSP, confronto con progetti pubblici su portatili con lo stesso chip audio. Nessun suono riprodotto, nessuna registrazione.

### 5a. Correzione della prima passata
Il sottografo `0xB0000003` del punto 2 **non è** la catena della musica sugli altoparlanti: contiene EC_SYNC e `0x070010A3`, che condivide parametri con il cancellatore d'eco (**dedotto**: percorso voce). La catena di riproduzione usa un modulo del costruttore che la prima passata non aveva cercato. Quindi la frase del punto 3 "non c'è un'equalizzazione fissa di Windows da copiare" è **sbagliata** per il lato DSP.

### 5b. Catena reale di Windows (**visto**)
- Registro, endpoint "Altoparlanti" (`MMDevices\Audio\Render\{72a99614-…}\FxProperties`): effetto di flusso (SFX) e di modalità (MFX) = wrapper Dolby `{0EBD8605-…}` e `{0EBD8606-…}` (in offload `…8611` e `…8612`); effetto di endpoint (EFX) = `{697DA8EE-…}` "ProxyAPOEFX" di Qualcomm (`ProxyAPO.dll`). Modalità: predefinita, media, film, comunicazioni (più grezza per MFX).
- `HKLM\SOFTWARE\Dolby\Wrapper`: i wrapper caricano gli APO Dolby veri `{E77F483A-…}` (SFX) e `{5CA784EC-…}` (MFX, EFX); `HKLM\SOFTWARE\Dolby\DAX\DolbyEnable=1`. DLL nel pacchetto `dax3_swc_aposvc_arm64…`: `DolbyDax3Apo.dll`, `DolbyAPOv251.dll`, `DolbyAPOv2100.dll`, `DolbyAPOvlldp*.dll`, servizio `DAX3API.exe`.
- `NumAPOInterfaces` e `APOInterface0={FD7F2B29-…}` nelle INF sono la normale registrazione di un APO (interfaccia IAudioProcessingObject), non un elenco di altri effetti. Che cosa faccia `ProxyAPO.dll` durante l'elaborazione: **ignoto**.
- DSP (ACDB), sottografo di elaborazione del dispositivo `0xB0000075` (gemelli `…35`, `…3F`, `…78`, `…7B`, `…7D`, `…81`, `…83`): `0x07001097` → SAL (limitatore) → SYNC → VOL_CTRL → **`0x0701000B`**; poi `0xB0000001`: SAL → SPLITTER → SPEAKER_PROTECTION v5 (`0x070010E2`) con VI (`0x070010E3`) e `0x070010E4` → CODEC_DMA_SINK.

### 5c. Moduli prima ignoti
| ID | Identità | Fonte |
|---|---|---|
| `0x07001019` | SOFT_PAUSE | **visto**: intestazione ufficiale `AudioReach/audioreach-graphservices`, `spf/api/modules/soft_pause_api.h` |
| `0x070010E4` | instradatore dei dati CPS della protezione v5 | riportato da `geocausa/SP11X1e-audio` (disassemblato sul firmware del Surface Pro 11); `PARAM_ID_CPS_CHANNEL_MAP_V5 0x080013CB` **visto** nell'intestazione ufficiale `cps_data_router.h` |
| `0x0701000B` | elaborazione degli altoparlanti del costruttore: incrocio, equalizzazione, compressori (forse `capi_msppv4`) | **dedotto** dai valori del punto 5d e da `nergzd723/xps13-9345-audio-softdsp` |
| `0x07001097` | **ignoto** (un progetto lo chiama SWR_SINK senza prova; qui è il primo modulo della catena) | |
| `0x07001068`, `0x070010A3` | **ignoti** | |

Firmware ADSP di questo PC (`qcadsp8380.mbn`, sha256 `654723125e69b09731325839be594cc189513fc6b2b0ad8f0dcc970d8215522d`): tabella di registrazione statica con record da 16 byte (ID, get_static_properties, init, classe) da `0x11d69c4` a `0x11d6e04`, 69 moduli (**visto**), fra cui `0x0701000A`, `0x0701000B`, `0x070010E2`, `0x070010E3`, `0x070010E4`, `0x07001097`, `0x07001068`; `0x070010A3` è registrato più avanti (`0x11d7c84`). È lo stesso file che carica Linux: i moduli ci sono già, manca la configurazione.

### 5d. Taratura Lenovo degli altoparlanti (modulo `0x0701000B`, parametro `0x0800137B`)
**Visto**: 54180 byte in virgola mobile, identici nelle 8 istanze. Altri parametri del modulo: `0x08001026` (abilitazione), `0x080010A6`, `0x080013C2`, `0x08001505`, `0x08001A5B`.
- Intestazione: dimensione `0xD3A0`; valore 4 (**dedotto**: canali); offset 16 = **2400,0** (**dedotto**: frequenza di incrocio woofer/tweeter in Hz; sul Dell XPS 13 lo stesso campo vale 2386); offset 20 e 24 = 1,122 (+1 dB); offset 56 = 64.
- Offset 1132 e 2508: due cascate di 12 biquad passa-alto (b0 b1 b2 a0 a1 a2 ≈ 0,99 −1,97 0,99 / 1 −1,97 0,97). Risposta complessiva di ciascuna cascata a 48 kHz: −113 dB a 80 Hz, −32 dB a 150 Hz, +1,7 dB a 300 Hz, piatta sopra 1 kHz. Come le 12 sezioni si dividano fra i canali: **ignoto**.
- Offset 37196 (12 sezioni) e 38572 (13 sezioni): due curve di equalizzazione. Guadagno in dB a 40 / 80 / 150 / 300 / 600 / 1k / 2k / 2,4k / 3k / 5k / 8k / 12k / 16k Hz:
  - curva 1: +0,1 +0,5 +1,6 +2,2 −1,5 −5,9 −4,3 +4,8 +0,5 +2,7 +4,4 +4,6 +3,0
  - curva 2: +0,2 +0,6 +2,2 +3,1 −1,4 −6,5 −3,3 +0,1 +0,4 +4,7 +6,9 +5,6 +1,2
  - **dedotto**: frequenza di campionamento 48 kHz e confini delle cascate. A quale canale appartiene ciascuna curva: **ignoto**.
- Il resto del blob (tabelle, compressori) non è decodificato.

### 5e. Altro
- `workspaceFile.qwsp`: 637312 byte, entropia 8,000 bit/byte, multiplo di 16, nessun blocco ripetuto: **cifrato** (**visto**). Chiave non cercata.
- ACDB, blocco `MODM`: solo 4 moduli dinamici, i codec Bluetooth (aptX adaptive, aptX classic, LC3 codificatore e decodificatore).
- Calibrazione per esemplare degli altoparlanti: sul Dell sta in `HKLM\SYSTEM\CurrentControlSet\Services\qcadcm\State\SpeakerProtectionInfo`; **su questo PC la chiave `State` è vuota** (letta senza privilegi elevati). Resistenza degli altoparlanti del Yoga: **ignota**.

### 5f. Progetti pubblici con lo stesso chip audio (amplificatori WSA884x)
- `nergzd723/xps13-9345-audio-softdsp` (Dell XPS 13 9345, 4 amplificatori come il Yoga): catena PipeWire e **compander degli amplificatori spento via UCM**. Motivo riportato: su Linux il driver usa tabelle per 8 ohm, gli altoparlanti sono da circa 4 ohm, e il compander acceso dava distorsione e tagli. Limiti di guadagno del kernel lasciati di serie.
- `geocausa/SP11X1e-audio` (Surface Pro 11, 2 amplificatori): protezione degli altoparlanti del DSP funzionante su Linux con una topologia AudioReach propria e patch al kernel. Dimostra che la parità con Windows è raggiungibile, ma con sviluppo e prove sull'hardware.
- `theflyingrahul/linux-hp-omnibook-5-glymur`: stessa struttura (`0xB0000075`, modulo `0x0701000D`, parametro `0x0800137B`).

### 5g. Che cosa cambia per Linux
1. Da provare sul portatile sotto Linux (reversibile): compander WSA884x spento nel profilo UCM, con misura al microfono, come nel progetto Dell.
2. Portare nella catena PipeWire i valori Lenovo (incrocio a 2400 Hz e le due curve) **solo dopo** aver capito a quali canali appartengono, e senza aumentare i guadagni degli amplificatori: su Linux manca la protezione.
3. Strada completa (sviluppo): topologia con `0x0701000B` e protezione v5, con invio dei parametri dell'ACDB, sul modello del progetto Surface.

Strumenti di questa passata (da WSL, percorsi in testa ai file): `tools/re-audio/win-pass2-moduli-firmware.sh`, `win-pass2-vendor0b-dove.sh`, `win-pass2-vendor0b-biquad.sh`.
