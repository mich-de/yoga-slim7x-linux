# 08 — Lavoro pubblico già esistente sul Dolby DAX3 (studio, 2026-11-17)

Obiettivo: sapere che cosa altri hanno già fatto per portare l'elaborazione Dolby DAX3 di un PC Snapdragon X su Linux, e quanto ci si può fidare, prima di fare qualsiasi cosa sul Yoga Slim 7x.
Legenda: **visto** = letto in un file (file:riga), **dedotto** = conclusione mia, **ignoto** = non verificato.
Abbreviazioni: `T` = clone del progetto gemello `github.com/geocausa/SP11X1e-audio` (commit unico `3232e1d`, 2026-10-05); `D` = cartella di studio con i binari Dolby del Yoga (`.../scratchpad/dolby`). Nessun sorgente altrui è copiato qui: solo riferimenti.

## 1. Progetto gemello (Surface Pro 11, X1E80100): che cosa ha fatto sul Dolby

### 1a. Tre generazioni di lavoro, in ordine di data

| Fase | Date | Che cosa | Stato oggi |
|---|---|---|---|
| A. DSP scritto da zero e tarato sulle misure | fino al 2026-08-03 | `dolby-port/sp11_dolby_dax.c` (livellatore, regolatore, PEQ "fittati" su misure in loopback: +8,01 dB a 1 kHz/−12 dBFS, +16,82 dB a 75 Hz/−30 dBFS) | **visto** `T/dolby-port/sp11_dolby_dax.c:2` "SUPERSEDED … DO NOT USE"; solo il PEQ è dichiarato ancora valido (`2026-08-04-DOLBY-PORT-STATE-OF-PLAY.md`, tabella File) |
| B. Decodifica statica di `DolbyAudioProcessing.dll` (Dolby Access/ASAR, 7.3.7.0) | 2026-08-01…04 | livellatore, regolatore, limitatore a inviluppo (dichiarato "exact": tetto −0,13 dBFS), exp2, PEQ, bass enhancer stadio 3 (decodificato ma mai attivo sul SP11). File `sp11_dolby_leveler/regulator/limiter/vlldp/chain.c`, plugin LADSPA `sp11_dolby_chain.so` | **visto** `STATE-OF-PLAY.md:1-3`: "HISTORICAL TARGET … Do not treat … as the production parity path". Catena mai misurata per intero (stesso file, "Where to pick up") |
| C. Esecuzione dei DLL Windows originali su Linux ARM64 ("ponte PE") | 2026-08-05…18 | caricatore PE + piccole emulazioni di runtime Windows; esegue il codice ARM64 originale di `DolbyApoVr.dll` → `DolbyAPOvlldp150.dll` dentro un plugin LADSPA | **visto** `2026-08-05-DOLBY-NATIVE-LIVE-COMPLETION.md:3-30`, `docs/audit/2026-08-08-DOLBY-INTEGRATION-STATUS.md`; sorgente `T/dolby-port/sp11_dolby_windows_chain_ladspa.c` |
| D. **UbiG**: reimplementazione pulita, senza DLL | 2026-08-20…26 | Stadio A (= VLLDP: banco di filtri 20 bande, compressore multibanda, regolatore, limitatore finale, postgain) e Stadio B (= VR: livellatore/DRC, IEQ, dialog enhancer, GEQ 20 bande), 7 profili, app di controllo GTK | **visto** `T/README.md:76-90`, `T/ubig/docs/STATUS.md:1-60`; promosso in produzione il 2026-08-24 |

### 1b. Catena ricostruita (fasi C e D)
- Ordine reale sul SP11, **visto** con trappole hardware via KDNET e dump di memoria completi di `audiodg`: `DolbyDax3Apo` (solo smistatore) → `DolbyApoVr` (livellatore, IEQ, dialog enhancer, regolatore, virtualizzatore) → `DolbyAPOvlldp150` (compressore multibanda, regolatore, limitatore finale). Fonti: `2026-08-06-DAX3-WRAPPER-DIRECT-PROCESSING-PROOF.md:5-10` (il wrapper non fa DSP), `2026-08-12-WINDOWS-VR-OWNS-PRE-VLLDP-DRIVE.md`, `T/dolby-port/sp11_dolby_windows_chain_ladspa.c:4-8` (VR alimenta VLLDP).
- Virtualizzatore per altoparlanti: **bypassato** per endpoint a 2 canali, come fa Windows (politica `bypass_stereo_virtualizer=true` dell'operatore Microsoft): **visto** `sp11_dolby_windows_chain_ladspa.c:169-185`. Conseguenza: sul SP11 "Music" e "Game" danno uscita identica bit per bit (**visto** `T/README.md:83-87`).
- Bassi virtuali / bass enhancer: decodificati ma spenti in tutti i profili del SP11 (**visto** `STATE-OF-PLAY.md`, "What this device actually runs").
- Spaziale/Atmos per oggetti (ASAR, `DolbyAudioProcessing.dll` + `DolbyHrtfEnc.dll`): ospitato su Linux come prova di laboratorio, escluso dal percorso altoparlanti (**visto** `2026-08-09-ASAR-WINDOWS-DOLBY-LINUX-HOST-BREAKTHROUGH.md:5-20`, `2026-08-08-DOLBY-INTEGRATION-STATUS.md`).

### 1c. DLL e versioni di Windows usate
- `DolbyAPOvlldp150.dll` sha256 `a2553ff7…f02c1`, `DolbyApoVr.dll` `1d74477e…5eecc`, `DolbyDax3Apo.dll` `6ea1702c…18d87`, tutti versione **3.30704.742.0** (settembre 2024): **visto** `2026-08-04-DOLBY-LIVE-KDNET-HOT-PATH.md:45,174-181`, `2026-08-11-youtube-vs-alerts-dolby-kdnet.md:23-25`, controllo impronte in `T/deploy/dolby/build-production.sh:12-13`.
- `DolbyAudioProcessing.dll` 7.3.7.0 (pacchetto DolbyAccessOEM 3.27.11070.0) sha256 `900944a1…0d0d3`: **visto** `KDNET-HOT-PATH.md:50-60`, `STATE-OF-PLAY.md`.
- Taratura: `DAX3_SPEAKER_TUNING_MSHW0486_REV0D.xml` (**visto** `2026-08-05-DOLBY-NATIVE-PROFILES.md`).
- Windows 11 build 26100.x/26200.x (24H2/25H2): **visto** come stringhe nei documenti di `docs/findings` (grep), senza legarle a una sola cattura.

### 1d. Metodo
Analisi statica (disassemblato ARM64, stringhe di log con nomi C++, RTTI), debug del kernel Windows dal vivo (KDNET da un secondo PC), dump di memoria completi durante la riproduzione, catture WASAPI grezze, confronto acustico fisico con un microfono esterno (Surface Pro 7) e registrazione nella stessa stanza; poi "oracoli differenziali": ogni funzione riscritta in UbiG è confrontata col codice originale caricato dal ponte PE su milioni di ingressi casuali. Regola di progetto: niente curve "fittate" (**visto** `2026-08-08-DOLBY-INTEGRATION-STATUS.md`, "Merge/deployment gates" punto 2).

### 1e. Fedeltà dichiarata e misurata
- Ponte PE (fase C): stato profilo VLLDP identico byte per byte allo snapshot Windows nelle regioni controllate; 1 000 000 di campioni senza NaN, uscita identica qualunque sia la dimensione del blocco host (**visto** `NATIVE-LIVE-COMPLETION.md`, sezioni "live-state byte match" e "Stress"). Non certificato 1:1 con Windows per contenuti e transizioni arbitrari (**visto** `INTEGRATION-STATUS.md`, "What is not proved").
- UbiG (fase D): sottofunzioni bit-esatte contro l'originale (es. limitatore 80 blocchi, compressore, livellatore 100 000 chiamate); catena Stadio B: 0 valori diversi su 7 profili × 200 000 campioni, 0/1 536 000 su 16 s con cambi di profilo (**visto** `T/ubig/docs/STATUS.md:122,843-849`). Prova acustica fisica Windows vs UbiG: 0,227 dB di errore medio da 315 Hz in su (**visto** `STATUS.md`, "M6 fresh Windows physical acoustic gate").
- Attenzione: un errore (tutti i profili predefiniti collassati) era sfuggito agli oracoli ed è stato scoperto solo ascoltando (**visto** `STATUS.md:91`). Il "bit-esatto" vale per i casi coperti dai test.

### 1f. Che cosa dichiara di non aver risolto
- Il vettore di 20 soglie logaritmiche del livellatore: famiglia nota, arrotondamento esatto non riprodotto, resta un dato fornito dal chiamante (**visto** `STATUS.md:330`).
- UbiG non è autosufficiente: richiede un **"owner pack" privato** (v4, sha256 `30b9b8ce…942df`) che contiene uno snapshot di stato a freddo di 298 937 byte e una finestra di dati immutabile copiata da `DolbyAPOVR.dll` all'indirizzo fisso `0x1801FF000` lungo `0xC2000` (**visto** `T/ubig/tools/build_stageb_v4_pack.py:1-20`, `STATUS.md:847-849`, `T/ubig/docs/SP11-CANDIDATE.md:5,23`). La "minimizzazione" pubblica di questi dati è dichiarata ancora da fare (**visto** `STATUS.md:68-72`).
- Profili diversi da quelli del SP11 a 2 canali, uscite multicanale, Atmos spaziale, cuffie: fuori ambito.
- Il resto del divario di volume fra Windows e Linux sul SP11 è stato attribuito alla catena di protezione/amplificatori, non al Dolby (**visto** `2026-08-18-DOLBY-EXONERATED-PROTECTED-PATH-LEVEL-LAW.md:1-5`).

## 2. Stessi DLL del Yoga? No

| File | SP11 (gemello) | Yoga (questo PC) |
|---|---|---|
| `DolbyAPOvlldp150.dll` | 3.30704.742.0, `a2553ff7…` | 3.30812.891.0, `ed832d8c…` |
| `DolbyAPOVR.dll` | 3.30704.742.0, `1d74477e…` | 3.30812.891.0, `b0383e0b…` |
| `DolbyDax3Apo.dll` | 3.30704.742.0, `6ea1702c…` | 3.30812.891.0, `7efca40d…` |
| `DolbyAudioProcessing.dll` (ASAR) | 7.3.7.0 | **assente** (solo il decoder Dolby Digital Plus in WindowsApps) |
| `DolbyHrtfEnc.dll` | presente | **assente** |

- Versioni Yoga: **viste** in `D/dis/<file>.str16.txt` (FileVersion, es. `DolbyAPOvlldp150.dll.str16.txt:780-781`). Impronte complete: `D/work/08/sha256-full.txt` (calcolate da `D/bin`). Il Yoga ha in più `DolbyAPOv251/v2100`, `vlldp`, `vlldp120/130/140`.
- Pacchetto driver Yoga: `dax3_ext_qc.inf` DriverVer 10.1117.422.3 del 2025-11-16 (**visto** riga 12), installazione `DolbyAccessNoGaming_V2` per `SUBSYS_IDEA4001` (**visto** riga 32).
- Gli indirizzi cablati nel ponte PE non valgono per il Yoga: alle RVA delle funzioni SP11 nei DLL del Yoga ci sono istruzioni a metà funzione (es. `0x1800DB270`, costruttore LibWrapperVr sul SP11, nel Yoga è `autibsp` di un epilogo; `0x18001F7A8`, orchestratore VLLDP, è un `add` interno): **visto** `D/dis/DolbyAPOVR.dll.dis.txt:204751`, `D/dis/DolbyAPOvlldp150.dll.dis.txt:27890`. Il plugin ha 58 costanti di indirizzo (**visto**, conteggio grep su `sp11_dolby_windows_chain_ladspa.c`). **Dedotto**: ogni indirizzo va ritrovato nella build del Yoga (per somiglianza di codice/stringhe), e anche gli offset delle strutture interne potrebbero essere cambiati.
- Il DLL VR del Yoga usa l'autenticazione dei puntatori ARM (`autibsp`) (**visto**); **dedotto**: su Linux le istruzioni PAC in spazio "hint" funzionano con le chiavi del processo, non dovrebbero bloccare il ponte; da verificare.
- Quale variante VLLDP (vlldp, 120…150) usa davvero il Yoga: **ignoto** (il gemello l'ha stabilito con trappole dal vivo; dall'INF si vede solo il wrapper `{0EBD85xx-…}`, righe 474-489).
- Taratura: stesso schema XML (10 profili, `tuning-cp` + `tuning-vlldp`, **visto** `D/pkg/…IDEA4001….xml:35-1439`) ma valori diversi. Per esempio sul Yoga in "dynamic" il livellatore è spento (`volume-leveler-enable=0`) e IEQ spento, mentre sul SP11 sono accesi (amount 5 e 10): **visto** `REVERSE-AUDIO-WINDOWS.md:15-20` contro `sp11_dolby_windows_chain_ladspa.c:160`. Le tabelle dei profili del gemello sono cablate nel C (righe 160-166) e nei JSON `T/ubig/specs/sp11-*-tuning-v1.json`, non lette dall'XML.

## 3. Licenze e condizioni
- Codice originale del gemello (anche `dolby-port/` e `ubig/`): **BSD-2-Clause** (`T/LICENSE:1`, `T/ubig/LICENSE:1`, `T/LICENSING.md` "Project-owned material"). I file di `dolby-port/` non hanno intestazione SPDX propria (**visto**, grep), quindi vale il default BSD-2. Basta conservare l'avviso di copyright.
- DLL Windows, tarature, dump, catture: **non** coperti dalla licenza, mai nel repository; "documentare come l'utente li ottiene legalmente" (**visto** `LICENSING.md`, "Third-party and vendor material").
- Fixture private (`dolby-port/PRIVATE-FIXTURES.md`): 8 file `.bin` con stato VLLDP catturato da Windows e vettori di prova, solo impronte nel repository; i test che li usano devono saltare in modo esplicito se mancano. Sono del SP11: per il Yoga **inutilizzabili** come riferimento (altra build, altra taratura, **dedotto**).
- UbiG: niente nomi Dolby nel codice nuovo, nessuna traduzione meccanica del decompilato, dati del dispositivo marcati `DEVICE_TUNING` (**visto** `T/ubig/docs/PROVENANCE.md`).
- **Dedotto**, per un uso personale: si possono riusare e adattare liberamente il caricatore PE, il ponte LADSPA, UbiG, gli strumenti e i test (BSD-2, citando la fonte). Non si possono ridistribuire i DLL né i pacchetti di dati generati da essi (owner pack, snapshot). Alcuni file BSD-2 contengono numeri estratti dai binari Dolby (es. `bass_coefficients.h`, `sp11_vlldp_fun18001de90_cdb_vectors.h` di 4 027 righe, le tabelle dei profili): la licenza del progetto non può dare diritti su dati Dolby. Per uso privato sul proprio PC con licenza il rischio è basso; per pubblicare va valutato. Valutazione legale vera: **ignota** (non sono un parere legale).
- Nel repository del proprietario: solo riferimenti, come richiesto.

## 4. Come gira su Linux nel gemello
- Formato: plugin **LADSPA** caricato da `filter-chain` di **PipeWire** (non ALSA diretto). Topologia "sink visibile + motore nascosto": `effect_input.sp11_ubig` → `effect_input.sp11_ubig_engine` (LADSPA `ubig_sp11_candidate`) → `effect_output.sp11_ubig` → sink ALSA degli altoparlanti (**visto** `T/deploy/ubig/98-sp11-ubig.conf.in:14-70`).
- Il ponte PE richiede memoria scrivibile+eseguibile: gira in un `filter-chain.service` separato con `MemoryDenyWriteExecute=no`; il demone PipeWire principale lo rifiuta (**visto** `NATIVE-LIVE-COMPLETION.md`, "Live PipeWire integration"). UbiG non ne ha bisogno (`MemoryDenyWriteExecute=yes`, **visto** `STATUS.md:97`).
- Solo 48 kHz, stereo, float32; altri formati: rifiuto (**visto** `T/ubig/docs/ARCHITECTURE.md`, "Adapter contract"; `sp11_dolby_windows_chain_ladspa.c:603`).
- Profili e parametri: ponte PE con variabile d'ambiente `SP11_DOLBY_PROFILE` (default Movie) e `SP11_DOLBY_GEQ` (righe 236-250, 318); UbiG con una pagina di controllo condivisa (mmap, generazione richiesta/conferma), `ubigctl` e l'app GTK `ubig-control` (7 profili + GEQ 20 bande −12…+12 dB). Il volume di sistema è passato al Dolby come postgain da un servizio di sincronizzazione (**visto** `T/deploy/ubig/sp11_ubig_volume_sync.py`, `STATUS.md` "Stage-A endpoint postgain").
- Latenza: catena VR→VLLDP→limitatore misurata **1 776 campioni = 37 ms** a 48 kHz (**visto** `sp11_dolby_windows_chain_ladspa.c:124-126`, `2026-08-13-PIPEWIRE-DOLBY-PAUSE-DRAIN.md:90`), più il quantum di PipeWire; accumulatore interno a blocchi da 256 campioni. CPU <1%, RSS ~28 MB col ponte PE (**visto** `NATIVE-LIVE-COMPLETION.md`).

## 5. Fonti pubbliche sul web (ricerche con termini generici)

| Fonte | Contenuto | Utilità |
|---|---|---|
| https://github.com/geocausa/SP11X1e-audio | il gemello (sopra) | **altissima**: unica ricostruzione seria di DAX3 su ARM64 trovata |
| https://professional.dolby.com/tv/dolby-advanced-audio-v2/ | descrizione pubblica dei blocchi: audio optimizer, audio regulator, volume maximizer (fino a +12 dB), dialog enhancer, volume leveler | bassa: solo nomi e scopo |
| https://professional.dolby.com/siteassets/pdfs/dolby-pc-entertainment-experience-v4-white-paper.pdf | white paper PC: intelligent equalizer, dialog enhancer, leveler (descrizione qualitativa) | bassa-media: aiuta a nominare i parametri dell'XML |
| https://professional.dolby.com/siteassets/pdfs/dolby-volume-tech-paper.pdf | principi del Dolby Volume (livellatore) | bassa-media: teoria del livellatore |
| https://android.googlesource.com/kernel/msm-extra/+/refs/tags/android-11.0.0_r0.42/asoc/msm-dolby-dap-config.h | header kernel Qualcomm (GPL-2.0) per DAP sul DSP: parametri DVLO/DVLI/VMB, 47 parametri, endpoint | bassa: è il DAP su DSP Android, non DAX3 per PC |
| https://developer.android.com/reference/android/media/quality/MediaQualityContract.SoundQuality | chiavi Android pubbliche per Dolby (on/off, volume leveler, Atmos) | bassa: solo interruttori |
| https://github.com/avisek/DolbyX | ospita `libdseffect.so` Android (DS1, ARMv7) su PC via QEMU, plugin VST2/LV2 per PipeWire; "uso personale"; v2 incompleta | media come idea (ospitare il binario originale), bassa per il codice: altro prodotto, altra architettura |
| https://github.com/shuhaowu/linux-thinkpad-speaker-improvements | risposta all'impulso registrata in loopback da Windows con Dolby attivo, applicata con il convolver di EasyEffects | media come ripiego rapido; perde tutta la parte dinamica (livellatore, regolatore, limitatore) |
| https://asahilinux.org/docs/sw/audio-userspace/ | modello Asahi: DSP degli altoparlanti in filter-chain di PipeWire con plugin LV2 propri | media: modello di integrazione e di sicurezza, non Dolby |
| https://learn.microsoft.com/en-us/windows/win32/api/audioenginebaseapo/nf-audioenginebaseapo-iaudioprocessingobject-getlatency | interfaccia APO (latenza, reset) | bassa-media: utile per chi ospita un APO |
| forum EasyEffects/JamesDSP/Equalizer APO | nessun ospite di APO Windows su Linux oltre al gemello | conferma che non c'è altro |

Non ho trovato documentazione pubblica dei nomi `dap_cpdp`, né dei codici a 4 lettere del DS1 Android (dvle, ieon, deon…) con il loro significato (**ignoto**; probabilmente solo nei moduli Magisk e nelle app decompilate, non usati qui).

## 6. Conclusione per il Yoga

**Utile così com'è (dedotto)**
- Il quadro della catena (wrapper senza DSP → VR → VLLDP, virtualizzatore bypassato in stereo, bassi spenti), da confermare sul Yoga ma con alta probabilità uguale perché stesso prodotto DAX3.
- Il caricatore PE generico (`sp11_vlldp_pe_loader.h`) e lo schema di integrazione PipeWire (filter-chain separato, sink visibile/motore nascosto, scarico alla pausa, sincronizzazione del volume come postgain).
- Metodo e regole: oracolo differenziale col DLL originale, niente curve fittate, test di dimensione del blocco, test di NaN.
- Il formato XML della taratura e il significato dei campi.

**Richiede adattamento**
- Ponte PE: ritrovare circa 58 indirizzi e gli offset di stato nella build 3.30812.891.0 (VR e VLLDP), più verificare quale variante VLLDP usa il Yoga. È il passo più corto per avere il Dolby "vero" su Linux.
- Profili: riscrivere le tabelle cablate con i valori dell'XML `IDEA4001` (oppure aggiungere un lettore XML).
- UbiG: il codice DSP è generico rispetto ai valori, ma il pacchetto dati (snapshot di 298 937 byte, finestra a `0x1801FF000`) va rigenerato dal ponte PE adattato al Yoga; i JSON `sp11-*` vanno sostituiti con quelli del Yoga; poi riverificare bit per bit contro i DLL del Yoga. Le funzioni di UbiG potrebbero differire se Dolby ha cambiato algoritmi fra 3.30704 e 3.30812 (**ignoto**).
- A valle: il Yoga ha un'altra catena DSP Qualcomm/amplificatori (vedi `REVERSE-AUDIO-WINDOWS.md` punti 5-8); la parità complessiva dipende anche da quella.

**Manca**
- Qualsiasi prova che la build del Yoga abbia gli stessi algoritmi (serve un confronto funzione per funzione fra le due build: al Yoga manca la copia SP11 dei DLL, che il gemello non pubblica).
- Riferimenti Windows del Yoga (catture, stato dei profili): le fixture SP11 non servono.
- Quale profilo usa Windows sul Yoga di default e quale variante VLLDP è caricata.
- Documentazione ufficiale dei parametri: non pubblica.

**Passo consigliato**: studio statico di corrispondenza fra le due build, senza eseguire nulla: per ognuno dei 58 indirizzi del ponte SP11 trovare la funzione corrispondente nel disassemblato del Yoga (stringhe di log, costanti, forma del codice) e scrivere una tabella SP11→Yoga in `D/work/`. Se quasi tutto si ritrova con piccoli spostamenti, la via è "ponte PE adattato → oracolo → UbiG con dati Yoga"; se gli algoritmi sono cambiati, partire dal ponte PE e lasciare UbiG per dopo.
