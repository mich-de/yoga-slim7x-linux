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

## 6. Terza passata (2026-11-16 notte, dalla live Fedora sul portatile, con misure ai microfoni interni)
Strumenti: `tools/misura-audio.py` (toni, sweep, catena simulata), `tools/ctl-amplificatori.sh` (controlli per numid, registro DRE_CTL_1).

### 6a. Amplificatori WSA884x su Linux 7.2.11: causa del volume basso (**visto**, misurato)
- Il driver della scheda (`sound/soc/qcom/x1e80100.c`) limita apposta `WSA*_RX* Digital Volume` a 81 (−3 dB) e `PA Volume` di Woofer/Tweeter a 6, con il commento "to reduce the risk of speaker damage until we have active speaker protection". Il modulo `wsagain` (parametro `cap`) alza solo questo tetto.
- Il driver dell'amplificatore (`wsa884x_mute_stream`) a ogni avvio del flusso mette CSR_GAIN_EN=1 (DRE_CTL_1 bit 0): guadagno fisso dato da `PA Volume`, letto **solo in quel momento** (cambiarlo mentre l'uscita è attiva non fa nulla; l'uscita si sospende dopo 5 s di silenzio).
- Scala misurata (tono 1 kHz, uscita lasciata sospendere fra le prove): `PA Volume` v vale 21 − 1,5×(31 − v) dB, cioè 17 = 0 dB, 31 = 21 dB; sotto circa 15 il guadagno resta al minimo. Valori 6 e 12: stesso livello; 17: +3,2 dB; 18: +4,7 dB.
- Azzerando CSR_GAIN_EN a metà tono (modulo di prova `audio/wsareg/`) il livello sale di **24 dB** (−43,1 → −19,1 dB): è il guadagno pieno dell'amplificatore (21 dB), quello che Windows può usare perché ha la protezione degli altoparlanti.
- Quindi Linux con il profilo UCM di serie (`PA Volume` 12, rimesso a ogni attivazione dell'uscita) suona circa 24 dB sotto il massimo dell'hardware. I valori 18/16 del 16/11 pomeriggio davano +4,7 dB sui woofer e nulla sui tweeter, e venivano poi riportati a 12 dall'UCM.
- `COMP Switch` degli amplificatori: nessun effetto; il compander del codec è già spento nel profilo UCM.
- Le scritture arrivano al chip (PA_FSM_EN=0 a metà tono → silenzio); nessun errore negli stati (INTR_STATUS a zero).
- Nei driver Windows (`qcaucd8380.sys`, `qcadcm8380.sys`, `qcaudminiport8380.sys`) non ci sono tabelle di registri WSA884x; la configurazione arriva dall'ACDB (`AcdbGetWsaCfg`, sezione GCLU/GCDT, moduli driver 0x8000020–0x8000090, non ancora interpretati) e il codice che scrive i registri è **ignoto** (**dedotto**: firmware ADSP).
- Ordine dei canali PCM confermato: 0,1 woofer, 2,3 tweeter. Sul bus SoundWire 1 ci sono i due woofer, sul 4 i due tweeter (**dedotto** dalle risposte misurate; i nomi del device tree non corrispondono).

### 6b. Altoparlanti misurati (un canale alla volta, guadagno ingresso → microfono)
- Woofer: sotto 250 Hz non emettono (−40 dB a 250 Hz, −27 a 500 Hz); picchi a 500 Hz e 1 kHz; calano sopra 1,6 kHz.
- Tweeter: 19 dB più sensibili dei woofer a 2 kHz; utili da 1,6 kHz.
- Sopra 8 kHz i microfoni interni hanno una risonanza (+10/+15 dB a 12,7 kHz su tutti i canali): misure non affidabili lì.
- Catena PipeWire del 16/11 pomeriggio (incrocio 3 kHz, tweeter −9 dB invertiti): buco di 11–14 dB a 2 kHz e acuti 6–8 dB sotto i medi. Causa del suono cupo.

### 6c. Struttura della taratura Lenovo (`0x0701000B` / `0x0800137B`, 54180 byte) (**visto**)
- 8 unità da 1376 byte, ciascuna = FIR (lunghezza 64, spazio per 256 prese) + 12 parole di opzioni + 12 biquad (b0 b1 b2 a0 a1 a2):
  - A (biquad a 1132), B (2508): passa-alto identici, FIR identità. 9 sezioni attive: −113 dB a 80 Hz, −32 a 150 Hz, piatto da 300 Hz.
  - C (37196, FIR a 36120), D (38572, FIR a 37496): le due curve del punto 5d. I FIR correggono ±2,5 dB fra 2 e 5 kHz.
  - E (49720), G (52472): FIR a zero; biquad piatti fino a 1 kHz, −2/−3 dB fra 2 e 5 kHz, +5/+10 dB a 12,7 kHz.
  - F (51096), H (53848): FIR identità; passa-alto ripido (−3,5 dB a 1 kHz, −19 a 500 Hz, −36 a 300 Hz) e taglio sopra 5 kHz.
- **Dedotto**: A,B e C,D = canali sinistro e destro prima della divisione; E,F,G,H = i quattro altoparlanti, con F e H = tweeter (passa-alto a 1 kHz). Il significato delle 12 parole di opzioni e dei FIR a zero di E e G è **ignoto**.
- Altro nel blob: tabelle da 1023 valori (6, da 3000 a 27628), un compressore a 23 bande (soglie da −10,5 a −24,9 dB, tempi, rapporti) a 34500–35800, due serie di 23 valori a 44556 e 44648 (**dedotto**: risposta misurata dei due lati per banda).
- Le curve non sono state copiate tali e quali: in Windows il guadagno relativo woofer/tweeter degli amplificatori è **ignoto**, e senza quello le curve da sole sbilanciano il suono.

### 6d. Nuova catena PipeWire (`audio/50-yoga-altoparlanti.conf`), tarata con le misure
Passa-alto 180 Hz del 4° ordine; incrocio LR4 a 2400 Hz (valore Lenovo); tweeter a −7 dB con la stessa polarità dei woofer; −4 dB a 560 Hz sui woofer; +3 dB a 6,5 kHz sui tweeter. Compressore, limitatore e limite dei bassi invariati.
Risultato misurato sulla catena vera (sweep a −42 dBFS, media dei due microfoni, 400–8000 Hz): scarto 3,4 dB → 1,8 dB; il buco a 2 kHz è chiuso (−17,5 → −10,6 dB con i medi a −7); acuti allo stesso livello dei medi (prima 6 dB sotto).
Costo: ai tweeter arriva più segnale di prima (+2 dB di livello, +3 dB a 6,5 kHz, banda da 2,4 kHz invece di 3). Resta sotto ciò che manda la taratura Lenovo (tweeter da 1 kHz), ma su Linux non c'è protezione.

## 7. Quarta passata (2026-11-16 notte, live Fedora): protezione altoparlanti del DSP, dati pronti per Linux
Obiettivo dell'utente: guadagno pieno (+24 dB) **solo** con la protezione dell'ADSP attiva. Qui: tutto ciò che serve dal lato Windows, estratto e verificato. Nessun modulo caricato, nessun guadagno toccato.

### 7a. Grafo di Windows, sottografo `0xB0000001` (**visto**, `tools/re-audio/acdb_graph.py`)
- Uscita (contenitore `0xE0000001`): SAL `0x4001` → CHMIXER `0x4AC9` → **SP_RX `0x411A`** (`0x070010E2`) → SPLITTER `0x4002` → LOG `0x4003` → CODEC_DMA_SINK `0x4157`.
- Ritorno V/I (contenitore `0xE0000036`): CODEC_DMA_SOURCE `0x411B` → LOG `0x411E` → **SP_VI `0x4121`** (`0x070010E3`).
- CPS (contenitori `…37`, `…38`, `…39`): CODEC_DMA_SOURCE `0x411C` e `0x411D` → LOG → MUX_DEMUX `0x4122` → instradatore CPS `0x4123` (`0x070010E4`).
- Control link (parametro APM `0x08001061`): SP_VI:`0x80000000` ↔ SP_RX:`0x80000000`, intento `0x08001204` (INTENT_ID_SP); CPS:`0x80000000` ↔ SP_RX:`0x80000001`, intento `0x08001537` (INTENT_ID_CPS). Proprietà di ogni link: `0x08001062` (lista intenti) e `0x0800136F = 1`.
- Stessa forma del Surface Pro 11 (là 2 altoparlanti, qui 4 in un solo modulo: il firmware ne accetta fino a 4, **visto** in `sp_vi.h` pubblico; il limite a 2 è solo del driver Linux).

### 7b. Tarature (**visto**, tabelle MTLU dell'ACDB, lette con `acdb_module_tag_inventory.py` del progetto `geocausa/SP11X1e-audio`, licenza BSD-2)
- Tag `0x0401000A` (SP_RX), righe per bit (16/24) e canali (2/4). Riga 4 canali: `0x080011E8` (68 B: 48 kHz, 4 altoparlanti, frame 1 ms, funzioni `0x1F`, controllo a 1000 Hz), `0x08001314`, `0x0800135A`, `0x08001367`, `0x0800150A`, `0x0800150E` (1212 B), `0x08001532` (1692 B).
- Tag `0x0401000B` (SP_VI), riga 4 canali: `0x080011F6` (44 B: 4 altoparlanti, **8000 Hz**, tono pilota 40 Hz), `0x08001203` (mappa canali 1…8 = V e I di ogni altoparlante), `0x08001384` (2084 B), `0x08001510` (temperatura massima, `0x1900` = 100 °C in Q6 per altoparlante), `0x08001535` (212 B).
- Tag `0x04010005` (endpoint V/I, modulo `0x411B`): **8000 Hz, 32 bit, 4 canali**; interfaccia LPAIF WSA (tipo 2), indice 1, maschera canali `0xF`. Conferma nel registro: `…\ADCM\SpkrProtVIInfo` = 8000 Hz, 32 bit.
- Taratura di sottografo (CDLU) per `0x411A` (18 parametri, fra cui `0x08001258` 1520 B e `0x0800134A` 2188 B), `0x4121` (9), `0x4123` (1): una sola variante per parametro, quindi nessuna ambiguità di chiave.
- Ordine di Windows (dal progetto gemello, driver `qcadcm8380.sys`): apertura grafo → taratura di sottografo → modo SP_RX `0x080011E9` → taratura con tag SP_RX → R0/T0 `0x080011F5` → modo VI `0x080011F4` → modo escursione `0x080011FF` → taratura con tag SP_VI → endpoint V/I → avvio.

### 7c. R0/T0 di questo portatile (**visto**, hive `SYSTEM`, `tools/re-audio/hive_spkr.py`)
`ControlSet001\Services\qcadcm\State\SpeakerProtectionInfo`: `NumChannels=4`, `UseCalibR0T0=1`.
| Canale | R0CalQ24 | R0 | T0CalQ6 | T0 |
|---|---|---|---|---|
| 0 | `0x03E209CC` | 3,883 Ω | 2709 | 42,3 °C |
| 1 | `0x03A3D5E7` | 3,640 Ω | 2816 | 44,0 °C |
| 2 | `0x04408F78` | 4,252 Ω | 2794 | 43,7 °C |
| 3 | `0x0401BAC7` | 4,007 Ω | 2666 | 41,7 °C |
Sono misure fatte da Windows su questi altoparlanti (non costanti di fabbrica). A quale altoparlante corrisponda ogni canale: **ignoto** (dedotto: ordine dei canali del DMA). `QCAUD\Feature\SpeakerProtection`: `SpeakerCoolDownTimerInSec=180`, `IsSpeakerProtQuickCalib=0`.

### 7d. File pronto per il DSP
`audio/protezione/yoga-slim7x-spkr-prot.bin` (15624 byte, 42 frame, sha256 `6556ac9667b2936c…`): frame APM `{iid, param_id, size, 0, dati allineati a 8}` nell'ordine di Windows (sottografo SP_RX e SP_VI, tag SP_RX, R0/T0 + modo normale con R0/T0 tarati + modo escursione 0, tag SP_VI). Gli IID sono quelli di Windows (`0x411A`, `0x4121`): la topologia Linux deve usare gli stessi. Si rigenera con `tools/re-audio/acdb_prot_blob.py` (i 12 parametri con tag sono stati riconfrontati byte per byte). Mancano di proposito CPS ed endpoint.

### 7e. Che cosa manca a Linux 7.2.11 (**visto** nei sorgenti)
- `audioreach.c`: per SP_RX manda solo il modo; per SP_VI modo, mappa e modo escursione, e rifiuta più di 2 altoparlanti. Nessuna taratura, nessun R0/T0, **nessun control link** (il parametro `0x08001061` non esiste nel driver), quindi SP_RX non riceve nulla da SP_VI.
- Topologia a monte del Yoga (`audioreach-topology`): senza moduli di protezione; i sorgenti m4 non hanno nemmeno le macro per quei moduli.
- Device tree: un solo collegamento `WSA_CODEC_DMA_RX_0` (4 canali, macro WSA + WSA2, 4 amplificatori). Nessun collegamento per il ritorno `WSA_CODEC_DMA_TX_0`. Ogni WSA884x ha la porta VISENSE (porte master 10 e 11) e il controllo `VISENSE Switch`; la macro ha il DAI `WSA_AIF_VI` (indice 2) e i controlli `WSA_SPKR_VI_1/2`.
- `x1e80100.c`: tetti a Digital Volume 81 e PA Volume 6, senza condizioni.

### 7f. Progetto gemello `geocausa/SP11X1e-audio` (letto: README, patch 0001–0049 per titoli, cinque documenti)
Ha la protezione funzionante sul Surface Pro 11 con un kernel 7.1.5 dedicato e circa 80 patch (control link, invio delle tarature frame per frame, ritorno V/I a 8 kHz, CPS, sequenze degli amplificatori). Lezioni utili qui: le tarature si mandano una per frame (un frame rifiutato non blocca gli altri); PBR e CPS dei due amplificatori condividono le porte master 7 e 13 e non vanno messe nello stream di riproduzione; il registro `TOP_CFG1=0x03` degli amplificatori fa uscire V e I alternati; il ritorno V/I va provato leggendo la telemetria (`0x080011F2`) e non dato per buono.

## 8. Protezione altoparlanti su Linux: prima prova sul DSP (2026-11-17 notte, live Fedora)
File e istruzioni: `audio/protezione/LEGGIMI.txt`. Stato e prossimi passi: `HANDOFF.md` punto 18. Nessun guadagno alzato.
- **Visto**: con la topologia nuova (SP_RX `0x411A`, sorgente V/I `0x411B`, SP_VI `0x4121`) e `snd-q6apm` modificato, l'ADSP apre il grafo (control link SP_VI↔SP_RX compreso) e accetta 45 frame di taratura su 45, inviati in banda uno per comando.
- **Visto** (rilettura con `APM_CMD_GET_CFG`): SP_RX `0x080011E9` = 0 (normale); `0x080011E8` = 48000 Hz, 16 bit, 4 altoparlanti, funzioni `0x1F`; `0x080011F3` = `05010200` (versione 5.1.2.0, parametro non presente nell'ACDB); SP_VI `0x080011F6` = 4 altoparlanti, 8000 Hz, tono pilota 40 Hz; `0x08001510` = `0x1900` ×4. Leggibili: `E8 EA EB F3` su SP_RX, `F4 F6 1510` su SP_VI; `F8` solo in calibrazione; errore 1 per `F2` (SP_RX), `FA FC 1201 150F` (SP_VI); gli identificativi pubblici della versione 7 (`0x08001B3C`…`5E`) non sono supportati (errore 3).
- **Misurato**: senza ritorno V/I, SP_RX in modo normale lascia il livello invariato entro 0,9 dB rispetto alla topologia di serie (toni a −40/−30/−20 dBFS, PA Volume 6).
- **Visto**: stato di calibrazione (`0x080011F8` di SP_VI: canali, stato, R0 in Q24): 1 senza ritorno; 2 e poi 7 (attesa V/I scaduta) dopo aver acceso il percorso V/I delle macro WSA e WSA2 (`TXn_SPKR_PROT_PATH_CTL` = 0x10, `TOP_CFG1` = 0x03). La sorgente V/I del DSP parte quindi con il solo clock delle macro; mancano i dati dagli amplificatori (porte SoundWire VISENSE).
- **Dedotto, non provato**: `VISENSE Switch` non può funzionare nello stream di riproduzione perché le porte master 10 e 11 sono porte di ingresso del controller.

## 9. Sesta passata (2026-11-17 mattina, live Fedora, skill leanrea): perché la calibrazione falliva
Cambio di metodo chiesto dall'utente: niente altri tentativi di calibrazione alla cieca, prima si ricava che cosa fa Windows. File: `audio/protezione/amplificatori/`, strumento `tools/re-audio/wsa_profilo.py`.

### 9a. Profilo degli amplificatori usato da Windows
- **Visto** (ACDB del Yoga, dati driver, decodificati con `tools/acdb_driver_data_inventory.py` del progetto gemello): modulo `0x08000090`/`0x08000091`, uscita 1 = sei parole `1, 3, 0, 4, 0, 1` (carico nominale **4 Ω**), identico al Surface Pro 11; modulo `0x08000020`/`0x08000022`, proprietà `0x10100006 = 0x24` = guadagno **18 dB** (non 21), per 2 e per 4 canali.
- **Visto** (`qcaucd8380.sys` 1.0.0.10778 del Yoga, sha256 `2771b797…79092c51`, `objdump -d`): il driver scrive davvero i registri WSA884x (correzione del punto 6a). `0x140032ac4…b70` sceglie `ISENSE2` (`0x3021`) da carico e guadagno (6 dB → `0x07`, 12 → `0x27`, 15 → `0x47`, 18 → `0x67`; 4 Ω a 18 dB → `0x07`); `0x140032ba8…c50` sceglie `VSENSE1` (`0x3020`) dal guadagno (`0x21`/`0x24` → `0x67`, `0x2a` → `0x87`).
- **Visto** (registri letti sul Yoga): Linux lascia `0x3020 = 0x87` (−24 dB) e `0x3021 = 0x27` (12 dB) e in tutto 28 registri diversi dalla sequenza a freddo di Windows (stadio di potenza compreso): `amplificatori/confronto-linux-2026-11-17.txt`.
- **Dedotto**: il resto del profilo (`profilo-windows-wsa884x.json`: 63 scritture a freddo, 10 all'avvio, 6 all'arresto) è la traccia del driver Windows sul Surface Pro 11; non ancora riscontrato registro per registro nel driver del Yoga.

### 9b. Taratura di SP_VI, parametro `0x08001535` (212 B) (**visto**, struttura `sp_vi_th_spkr_param_t` di `sp_vi.h`)
Per altoparlante (0…3): resistenza di riserva 4,307 / 3,689 / 4,327 / 3,597 Ω; tono pilota `0x0a3d` = −40 dBFS; resistenza delle piste 0,130 / 0,130 / 0,107 / 0,112 Ω; tensione di picco a fondo scala digitale 10,96 / 11,05 / 10,93 / 11,07 V; da digitale a volt 15,07 / 15,17 / 15,14 / 15,15; da digitale ad ampere 7,01 / 7,05 / 7,02 / 7,03; soglia del pilota `0x4000` = 25 % dell'atteso. In coda, per altoparlante: attesa 100 ms, calibrazione 2000 ms, attesa V/I 100 ms (2000 ms nella riga a 2 canali).

### 9c. Le due cause (**misurato**)
1. **Trasporto**: nel device tree le porte 10 e 11 dei controller WSA/WSA2 hanno `qcom,ports-offset2 = 0xff`. Nel controller Qualcomm `Offset2 + 1` è la distanza fra i canali di una porta (COMP: 7 → ogni 8 bit; BOOST: 0x1f → ogni 32): con `0xff` il secondo canale ricade sullo stesso bit del primo, quindi V = I. Il DSP calcolava R = (da digitale a volt)/(da digitale ad ampere) − piste = 15,07/7,01 − 0,13 = **2,019 Ω**: letti 2,025 (altoparlante 0) e 2,058 (altoparlante 3, atteso 2,044), e la lettura non cambiava spostando i guadagni dei sensori di 6 e 3 dB. Windows su quelle porte scrive `Offset2 = 0` prima di avviare il grafo (traccia del progetto gemello: porta 10 `0x0300060f`, porta 11 `0x03000d0f`, stessi offset del Yoga).
2. **Livello**: con `Offset2 = 0` i dati sono veri ma lo stato diventa 7 (attesa V/I scaduta). Il pilota atteso è 0,01 × 10,96 V = 0,110 V di picco, soglia 25 % = 0,027 V; con `PA Volume` 18 l'amplificatore è a 1,5 dB invece dei 18 dB di Windows, cioè 0,016 V: sotto soglia. La taratura presume l'amplificatore a 18 dB (`PA Volume` 29).
- Ordine di Windows (progetto gemello, traccia a freddo): prima `GLOBAL_PA_EN = 1` sui due amplificatori, poi i clock di protezione delle macro; l'ordine inverso dava guasti dell'amplificatore. `wsavi` lo rispetta (si carica mentre suona).

### 9d. Controllo termico di SP_RX, parametro `0x08001532` (1692 B a 4 canali) (**visto**, strutture `param_id_sp_dynamic_cfg_t` e `sp_th_ctrl_param_t` di `sp_rx.h`)
- Parte comune (parole da 30): canali collegati 1, **metodo 2** (temperatura stimata in avanti), temperatura presunta all'avvio 50 °C, misure accettate fra −30 e 200 °C, variazione massima 64 °C/s, **attenuazione massima −12 dB**, zona morta 1 °C.
- Per altoparlante (10 parole da 71, 81, 91, 101): pilota −40 dBFS, bobina 4,30 / 3,69 / 4,32 / 3,59 Ω, fondo scala 10,96 / 11,04 / 10,89 / 11,06 V, resistenza termica 37,3 °C/W, costanti di tempo 1,85 e 7,41 s, **obiettivo 90 °C** (`0x1680`, parola 78 + 10k), termini P e I `0x1302`, `0x866`.
- Corrispondenza degli identificativi fra versione 5 (Yoga) e 7 (pubblica), per posizione: `E9`→`B40` modo, `EA`→`B41`, `EB`→`B42`, `ED`→`B44`, `EE`→`B45`, `EF`→`B46` statistiche termiche, `F0`→`B47`, `F1`→`B48`, `F2`→`B49` massimi; la configurazione dinamica è `0x08001532`. Le quattro statistiche sono rifiutate in lettura dal firmware del Yoga (**visto**).

### 9e. Prove sul portatile (**misurato**, 17/11): `HANDOFF.md` punto 21
Calibrazione riuscita a 18 dB (3,840 / 3,594 / 4,218 / 3,983 Ω contro 3,883 / 3,640 / 4,252 / 4,007 di Windows). Protezione termica: abbassando l'obiettivo sotto la temperatura delle bobine il DSP attenua di 11–12 dB; con obiettivo 45 °C attenua solo senza ritorno V/I (temperatura presunta 50 °C), mentre con il ritorno toglie l'attenuazione in 3 s: usa la temperatura misurata.
