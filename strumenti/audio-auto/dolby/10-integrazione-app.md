# Compito 10 - Integrazione con PipeWire e progetto dell'app

Data: 2026-11-17. Fase: STUDIO e PROGETTO (nessun programma scritto, nessuna configurazione cambiata).
Nome di lavoro dell'app: "Audio Yoga" (nome definitivo da decidere, vedi sezione 7). Nessun marchio Dolby
nell'interfaccia: i nomi Dolby restano solo nei file tecnici interni.

Legenda: **visto** = comando o file controllato (indicati); **dedotto** = ragionamento da fatti visti o da
documentazione nota; **ignoto** = da verificare.

Prove grezze salvate in
`/tmp/claude-1000/-run-media-liveuser-Volume-linux/747a0e5d-c8cd-40ba-973d-676e005c4581/scratchpad/dolby/work/10/`
(`pw-dump.json`, `pw-top.txt`; area temporanea, si perde al riavvio).

---------------------------------------------------------------------------------------------------

## 1. Fotografia della catena audio attuale

### 1.1 Versioni e servizi
- PipeWire 1.6.9, WirePlumber 0.5.18 (**visto**: `pipewire --version`, `wireplumber --version`).
- Servizi utente attivi: `pipewire`, `wireplumber`, `filter-chain` (processo separato, `pipewire -c filter-chain.conf`,
  PID diverso dal demone) (**visto**: `systemctl --user status`).
- `filter-chain.service`: `Restart=on-failure`, `BindsTo=pipewire.service`, `MemoryDenyWriteExecute=yes`,
  `SystemCallFilter=@system-service` (**visto**: `systemctl --user cat filter-chain.service`). Conseguenza
  (**dedotto**): un plugin caricato nella filter-chain non può usare codice generato a runtime (W+X); mmap di memoria
  condivisa, futex, eventfd e socket Unix sono permessi da `@system-service`.
- Livello Pulse: "PulseAudio (on PipeWire 1.6.9)", formato predefinito float32le 2ch 48000 Hz, uscita predefinita
  `effect_input.yoga_spk` (**visto**: `pactl info`).

### 1.2 Clock (metadati `settings`, **visto** in `pw-dump`)
```
clock.rate = 48000      clock.allowed-rates = [ 48000 ]   (solo 48 kHz: nessun cambio di frequenza)
clock.quantum = 1024    clock.min-quantum = 32            clock.max-quantum = 2048
clock.force-quantum = 0 clock.quantum-limit (nodi) = 8192
```
Quantum predefinito 1024 campioni = 21,3 ms a 48 kHz. Quantum effettivo in riproduzione: **ignoto** (al momento
della misura nessun flusso suonava: in `pw-top` tutti i nodi `S` sospesi, `effect_output.yoga_spk` `I` idle,
quantum 0; **visto** in `pw-top.txt`). Non si è fatto suonare nulla per rispettare i limiti del compito.

### 1.3 Grafo
```
  applicazioni (Firefox, VLC, ... formato qualsiasi, convertito da PipeWire)
        |  (default.audio.sink = effect_input.yoga_spk)
        v
 +--------------------------------------------------------------+   processo filter-chain.service
 | id 53  effect_input.yoga_spk   Audio/Sink  F32P 2ch FL FR    |   descr. "Altoparlanti potenziati"
 |   hp 180 Hz LR4 -> sc4 (-24 dB 3:1 +12) -> limitatore -1,5   |
 |   -> woofer: bassi<650 limitati -9 dBFS, -4 dB a 560, LP 2,4k|
 |   -> tweeter: HP 2,4k, +3 dB a 6,5k, x0,45                   |
 | id 71  effect_output.yoga_spk  Stream/Output/Audio F32P 4ch  |   node.passive = true
 +--------------------------------------------------------------+   target.object = ALSA speaker
        |  4 link (porte 59,72,73,78 -> 48,49,50,36), stato "paused"
        v
 id 65  alsa_output.platform-sound.HiFi__Speaker__sink   Audio/Sink, S16LE 4ch 48 kHz FL FR RL RR
        priority.session 728, api.alsa.path hw:X1E80100LENOVOY,1, soft-mixer (51-yoga-soft-mixer.conf)
        |  FL,FR = woofer   RL,RR = tweeter (taratura 16/11)
        v
 amplificatori WSA884x (guadagno PA da audio-ampli.sh)
```
Fonti (**visto**): `pw-dump` (nodi 53, 65, 71, link, formati `EnumFormat`), file
`/etc/pipewire/filter-chain.conf.d/50-yoga-altoparlanti.conf` righe 11-84 (uguale a `K/audio/50-yoga-altoparlanti.conf`).
Il nodo `effect_input.yoga_spk` non ha `priority.session` (**visto**: assente nelle proprietà del nodo 53).
Volume utente: `channelVolumes` 0,166 su `effect_input.yoga_spk`, 1,0 sull'ALSA (**visto**, Props).

### 1.4 Dispositivo
- Scheda `alsa_card.platform-sound`, profilo HiFi via UCM; rotte: solo `[Out] Speaker` e `[In] Mic`
  (**visto**: `EnumRoute` in `pw-dump`).
- UCM `Slim7x-HiFi.conf`: solo `SectionDevice."Speaker"` e `"Mic"`, nessun Headphones/Headset (**visto**: grep righe 19, 37).
  **Dedotto**: questo portatile non ha presa jack da 3,5 mm gestita; le cuffie possibili sono Bluetooth o USB-C,
  che compaiono come uscite separate.

### 1.5 Latenza attuale
- Filtri builtin (biquad, mixer, copy, linear): latenza 0 (**dedotto**).
- `fast_lookahead_limiter`: ha un lookahead e un'uscita di controllo "latency" (**dedotto** dal plugin SWH; valore
  esatto **ignoto**). Il filter-graph di PipeWire legge le porte "latency" dei plugin (**visto**: stringhe
  `"%s latency:%f-%f"` e `"graph latency min:%f max:%f"` in `libspa-filter-graph.so`).
- Latenza ALSA (periodi, headroom): **ignota** (dispositivo sospeso al momento della misura).

### 1.6 Materiale disponibile sulla live (**visto**: `rpm -qa`, `ls`)
- Moduli: `module-filter-chain`, `module-pipe-tunnel`, `module-loopback`, `module-parametric-equalizer`, ecc.
- Plugin filter-graph: builtin, ladspa, ebur128. **LV2 assente** (nessun `libspa-filter-graph-plugin-lv2.so`,
  nessuna cartella `/usr/lib64/lv2`; c'è solo `lilv-libs`).
- `pipewire-jack-audio-connection-kit(-libs)` installati; modulo Python `jack` assente.
- `gcc` e `make` presenti; `pipewire-devel` e `python3-devel` assenti.
- Python: PySide6 6.11.2 (con QtDBus e QtNetwork), numpy 2.5.4, dbus-python, python3-gobject.
- KDE: `kf6-kstatusnotifieritem` presente (non serve a Qt, che parla da sé il protocollo del vassoio).

---------------------------------------------------------------------------------------------------

## 2. Dove e come inserire il processore esterno (2 canali, prima di "Altoparlanti potenziati")

Componenti in gioco (nomi di lavoro):
- **ospite**: il processo che contiene il motore (DLL Dolby ospitate; progetto degli altri agenti). Pesante, può
  mancare, può morire.
- **ponte**: il pezzo che sta dentro il grafo di PipeWire, prende i campioni, li dà all'ospite e li riprende.
  Deve essere piccolo, senza allocazioni e senza attese illimitate nel thread in tempo reale.
- **canale dati**: memoria condivisa fra ponte e ospite (stessa per tutte le strade a, c, d).

### 2.1 Confronto

| | (a) nodo nativo pw_filter/pw_stream | (b) module-pipe-tunnel sink+source | (c) client JACK su PipeWire | (d) plugin LADSPA nella filter-chain |
|---|---|---|---|---|
| Dove sta | nuovo processo, nuovo nodo "Audio/Sink" collegato a `effect_input.yoga_spk` | due nodi del modulo + FIFO + loopback | nuovo processo con API JACK | primo nodo dentro `50-yoga-altoparlanti.conf` |
| Latenza aggiunta | blocco B (5,3 ms con B=256) in modo sincrono; B + 1 quantum in asincrono | buffer del pipe: 64 KiB = 8192 frame F32 stereo = fino a 170 ms, variabile (**dedotto**) | come (a) | come (a): B sincrono, B + quantum asincrono |
| Clock | segue il grafo | due domini di clock, serve ricampionamento adattivo; deriva | segue il grafo | segue il grafo |
| Ospite assente/morto | il ponte passa il segnale diretto (riserva) | il FIFO si blocca o si svuota: silenzio o salti | come (a) | il plugin passa il segnale diretto |
| Ponte morto | il nodo sparisce: WirePlumber sposta i flussi sull'uscita di priorità più alta, che oggi è l'ALSA grezza (728) e salta crossover e limitatore (**dedotto**) | flussi interrotti | come (a) | cade tutta la filter-chain; systemd la riavvia (`Restart=on-failure`, **visto**); per ~1 s i flussi vanno sull'ALSA grezza (**dedotto**) |
| Uscita predefinita | cambia (nuovo sink) e va mantenuta da `utente-login.sh` | cambia | serve una regola, i client JACK non sono sink del desktop (**dedotto**) | non cambia: resta `effect_input.yoga_spk` |
| Da compilare | C con `pipewire-devel` (assente, va messo nel kit) | nulla | C o Python con libjack (shim presente) | C con il solo `ladspa.h`; `gcc` c'è |
| Comandi | da inventare | nessuno | da inventare | porte di controllo LADSPA (`pw-cli set-param ... Props`) oppure area di comando nella memoria condivisa |
| Complessità | media (API PipeWire, ciclo di vita, link) | bassa da installare, alta per farla andare bene | media | bassa: ~300 righe C, nessun nuovo nodo |

### 2.2 Scelta consigliata: (d) plugin LADSPA "ponte" come primo nodo della filter-chain
Perché (**dedotto** dai punti visti sopra):
1. Nessun cambio del grafo: niente nuovo sink, niente collegamenti da gestire, uscita predefinita invariata;
   `utente-login.sh` resta com'è.
2. La riserva è naturale: se l'ospite manca il plugin copia l'ingresso sull'uscita e la catena di protezione
   (passa-alto, compressore, limitatori) resta SEMPRE dopo il motore. Con (a) se muore il ponte si perde anche la
   protezione.
3. Il codice nel processo filter-chain è minimo (copie in memoria condivisa): il codice Dolby pesante sta
   nell'ospite, in un altro processo. Un crash del motore non tocca l'audio.
4. Compilabile con quello che c'è (`gcc`, header LADSPA pubblico), stesso schema di consegna di `sc4_1882.so`
   (file .so nel kit copiato in `/usr/lib64/ladspa`).
5. Latenza riportata a PipeWire con una porta di controllo di uscita "latency" (convenzione LADSPA che il
   filter-graph legge: stringhe **viste**; comportamento esatto con questo plugin **ignoto**, da provare).

Limite: LADSPA non ha chiamate asincrone né messaggi; tutto ciò che non è un numero (profilo, 20 bande) passa
dall'area di comando nella memoria condivisa, non dalle porte. Va bene: le porte LADSPA servono solo per lo
stato "bypass forzato" e per leggere la latenza.

Seconda scelta: (a) con `pw_filter`, se le prove mostrassero problemi del filter-graph con il plugin (per esempio
la latenza non riportata). In quel caso serve dare a `effect_input.yoga_spk` una `priority.session` più alta
dell'ALSA (oggi 728) perché in caso di caduta del ponte i flussi tornino sugli "Altoparlanti potenziati" e non
sull'ALSA grezza. Scartate: (b) per latenza e clock, (c) perché è (a) con un livello in più e senza vantaggi.

### 2.3 Schema proposto
```
 app (PySide6) --socket Unix JSON--> servizio di controllo --area comandi--+
                                       (stato.json)                        |
                                                                           v
 applicazioni -> effect_input.yoga_spk                              +-------------+
                 [ponte LADSPA] --blocchi B frame-> memoria    <--> |   ospite    |
                      ^   |      <-blocchi elaborati- condivisa      | (motore DAX)|
                      |   | riserva: ingresso ritardato di B         +-------------+
                      |   v                                           Restart=always
                 hp 180 -> sc4 -> limitatore -> crossover -> effect_output -> ALSA 4ch
```

### 2.4 Memoria condivisa (protocollo ponte <-> ospite, versione 1)
- File `$XDG_RUNTIME_DIR/audio-yoga/dati.shm` (tmpfs dell'utente, già con permessi 0700) creato dall'ospite;
  il ponte lo apre in sola lettura+scrittura se esiste, altrimenti riprova ogni ~1 s fuori dal thread audio
  (**dedotto**: aprire file nel thread RT non va fatto).
- Intestazione: magia, versione, frequenza 48000, canali 2, B, contatore battito dell'ospite, contatore cicli del
  ponte, stato (0 assente, 1 pronto, 2 elaborazione), latenza interna del motore in frame.
- Due anelli SPSC di blocchi F32 interlacciati da B frame: ingresso (scrive il ponte) e uscita (scrive l'ospite),
  indici atomici.
- Risveglio: futex sulla parola "blocchi in ingresso" (o eventfd passato su socket). Quale dei due dipende da come
  è fatto l'ospite (se è un processo Wine il codice Windows non vede il futex: serve un thread nativo nel
  lanciatore) - **ignoto**, da concordare con gli agenti dell'ospite.
- Area comandi separata (non nel percorso audio): numero di sequenza + blocco parametri, scritta dal servizio di
  controllo, letta dall'ospite fra un blocco e l'altro.

### 2.5 Riserva (l'audio non si interrompe mai)
Regole del ponte, per ogni ciclo:
1. Ospite "vivo" = battito cambiato negli ultimi 200 ms e versione compatibile.
2. Modo sincrono: il ponte mette i blocchi completi, sveglia l'ospite e aspetta al massimo una scadenza
   (es. 30% della durata del quantum). Se il blocco elaborato arriva, lo usa.
3. Se la scadenza passa o l'ospite non è vivo: usa l'ingresso ritardato degli stessi B frame (così la latenza non
   cambia e non ci sono salti) e fa una dissolvenza incrociata di ~10 ms fra elaborato e diretto.
4. Al ritorno dell'ospite: dissolvenza inversa dopo almeno 2 blocchi buoni consecutivi.
5. Il ponte non alloca, non apre file e non scrive log nel thread RT; segnala lo stato su una porta di controllo
   di uscita (0 diretto, 1 elaborato) che il servizio di controllo legge con `pw-dump`/`pw-cli`.
6. Errore di versione o di formato: diretto permanente, finché la memoria condivisa non viene ricreata.
Effetti visibili all'utente: con motore assente si sente l'audio come oggi (catena "Altoparlanti potenziati");
l'app mostra "Motore non attivo - audio diretto".

---------------------------------------------------------------------------------------------------

## 3. Blocchi fissi e quantum variabile

- PipeWire chiama il plugin con N = quantum frame, da 32 a 2048 (**visto** min/max), tipicamente 1024 sul
  desktop; può cambiare quando un'applicazione chiede latenza bassa (**dedotto**: `node.latency` dei client).
- Frequenza: sempre 48 kHz (`clock.allowed-rates = [48000]`, **visto**). La taratura Dolby è a 48000
  (`endpoint fs="48000"`, **visto** nell'XML). Nessun ricampionamento necessario; il ponte rifiuta (riserva)
  qualsiasi altra frequenza.
- Soluzione: FIFO di ingresso e di uscita di B frame nel ponte. Si pre-riempie l'uscita con B frame di silenzio;
  ogni ciclo si accodano N frame, si elaborano tutti i blocchi completi, si estraggono N frame. Latenza aggiunta
  costante = B, indipendente dal quantum, riportata con la porta "latency".
  - B = 256 -> 5,3 ms; B = 512 -> 10,7 ms; B = 480 (10 ms, periodo tipico degli APO di Windows) -> 10 ms.
  - Valore di B richiesto dal motore: **ignoto** (da studio dell'ospite). Se il motore accetta blocchi variabili,
    usare la dimensione più piccola che accetta.
- Con quantum >= B e multiplo di B (1024 con B 256) il lavoro per ciclo è regolare (4 blocchi). Con quantum
  piccoli (32-128) alcuni cicli non elaborano nulla e altri un blocco intero: il costo è a scatti ma la latenza
  resta B (**dedotto**).
- Modo asincrono (se l'ospite non può rispondere entro la scadenza in modo affidabile): il ponte consegna e
  ritira senza attendere; latenza = B + 1 quantum, variabile con il quantum. Da usare solo se il sincrono dà
  troppi passaggi in riserva.
- Latenza interna del motore (lookahead di regolatore e livellatore): **ignota**; va sommata e dichiarata.
- Non serve forzare il quantum (`clock.force-quantum`); opzionale fissare `node.latency = 1024/48000` nelle
  `capture.props` per evitare quantum minori di B: decisione del proprietario (vedi 7).

---------------------------------------------------------------------------------------------------

## 4. Canale di comando fra app e motore

### 4.1 Chi tiene lo stato
Un **servizio di controllo** utente (`audio-yoga-motore.service`, lo stesso che lancia e sorveglia l'ospite) è
l'unico a scrivere lo stato. L'app è solo un'interfaccia: se è chiusa, lo stato vale lo stesso; se si apre, legge
lo stato dal servizio. Così all'accesso basta il servizio e l'app non è necessaria.

### 4.2 Mezzo: socket Unix con righe JSON
`$XDG_RUNTIME_DIR/audio-yoga/controllo.sock`, solo l'utente (cartella 0700).
Confronto (**dedotto**):
- Socket Unix + JSON: lo parla Python (QLocalSocket di QtNetwork, **visto** disponibile), C, e il lanciatore
  dell'ospite; permette risposte ed eventi; nessuna dipendenza. Consigliato.
- D-Bus di sessione: introspezione e attivazione automatica gratis, ma aggiunge un file di servizio, una
  libreria nel lato motore e un altro posto dove può fallire; utile solo se altre app dovessero comandarlo.
- File di stato osservato (inotify): semplice ma senza risposta né stato "motore vivo"; resta solo come
  memoria persistente.

### 4.3 Messaggi (versione 1)
Richieste dell'app:
```
{"v":1,"cmd":"stato"}                                  -> risposta con lo stato completo
{"v":1,"cmd":"iscrivi"}                                -> da qui riceve gli eventi
{"v":1,"cmd":"profilo","nome":"film"}                  dinamico | film | musica | spento
{"v":1,"cmd":"imposta","surround":{"on":true,"db":6}}
{"v":1,"cmd":"imposta","dialoghi":{"on":true,"q":5}}   q 0-16
{"v":1,"cmd":"imposta","livellatore":{"on":false,"q":5}}  q 0-10
{"v":1,"cmd":"imposta","eq":{"on":true,"modo":"dettagliato","bande":[0,...]}}  20 valori in dB
{"v":1,"cmd":"imposta","volmax":true}
{"v":1,"cmd":"ripristina","nome":"film"}               torna ai valori della taratura
```
Eventi del servizio:
```
{"v":1,"ev":"stato","profilo":"film","surround":{...},...,
 "motore":"attivo|assente|riserva","uscita":"altoparlanti|altro","latenza_ms":5.3,"errore":""}
```
Il servizio valida i valori (limiti della sezione 5.4), li traduce in parametri del motore (unità Dolby: 1/16 dB,
nomi dell'XML) e li scrive nell'area comandi. Le modifiche dell'utente sono salvate **per profilo** come
differenze rispetto alla taratura (come fa l'app di Windows: **dedotto**, non verificato).

### 4.4 Salvataggio e ripristino
- File `~/.config/audio-yoga/stato.json`: profilo attivo + differenze per profilo; scrittura atomica (file
  temporaneo + rename) al più una volta al secondo.
- All'accesso: systemd utente avvia il servizio (vedi 6), che legge `stato.json` (o il profilo "dinamico" della
  taratura se manca o è rotto), avvia l'ospite, scrive l'area comandi. Nessun intervento dell'utente.
- Il ponte e la filter-chain non hanno stato da salvare.

---------------------------------------------------------------------------------------------------

## 5. L'app

### 5.1 File (proposta, tutti nel kit sotto `audio-auto/dolby/app/`)
```
app/
  audio_yoga.py         finestra PySide6 + icona nel vassoio (un solo file, client del socket)
  motore/
    controllo.py        servizio di controllo: socket, stato.json, taratura -> parametri, sorveglia l'ospite
    taratura.py         lettura dell'XML (stdlib xml.etree), usata da controllo.py
  ponte/
    yoga_ponte.c        plugin LADSPA (sezione 2), compilato una volta per aarch64
    yoga_ponte.so
  audio-yoga.svg        icona propria (nessun logo Dolby)
  audio-yoga.desktop    voce di menu
  audio-yoga-vassoio.desktop   avvio automatico (solo se si sceglie il vassoio)
  audio-yoga-motore.service    unità systemd utente
```
L'XML di taratura resta dov'è nel kit (`K/audio/windows/`, **visto** citato in HANDOFF.md riga 8) e viene
copiato accanto al servizio all'installazione.

### 5.2 Lettura dei profili
`taratura.py` legge `endpoint type="internal_speaker"` (l'unico presente, **visto**) e i `profile type=` richiesti:
`dynamic`, `movie`, `music`, `off` -> Dinamico, Film, Musica, Spento. Risolve i riferimenti `preset=` alle
costanti (`ieq_detailed`, `ieq_balanced`, `ieq_warm`, `array_20_zero`, **visto**) e usa `band_20_freq fs_48000`
(47 ... 19688 Hz, **visto**). Gli altri profili presenti (`game`, `voice`, `voice_onlinecourse`,
`personalize_user1-3`, **visto**) restano disponibili ma nascosti (decisione 7).

### 5.3 Avvio
- Voce di menu "Audio Yoga" nella categoria Impostazioni/Audio (`/usr/share/applications`).
- Vassoio di Plasma: consigliato SÌ, icona piccola con menu rapido (4 profili + "Apri") e clic che apre la
  finestra; `QSystemTrayIcon` di Qt 6 usa il protocollo StatusNotifierItem che Plasma mostra (**dedotto**).
  Avvio automatico del solo vassoio da `/etc/xdg/autostart`. Alternativa senza vassoio: solo voce di menu
  (il servizio lavora comunque).
- Una sola istanza: il secondo avvio porta in primo piano la finestra esistente (socket locale dell'app).

### 5.4 Valori dell'XML e cosa vede l'utente
Unità Dolby: guadagni in 1/16 dB (**dedotto** dalla convenzione Dolby DAP e coerente con 96 = 6 dB nello schema
approvato; `REVERSE-AUDIO-WINDOWS.md` riga 14 riporta la stessa convenzione).

| Funzione (app) | Parametri XML | Valori nella taratura (dinamico/film/musica/spento) | Mostrato |
|---|---|---|---|
| Surround virtuale | `surround-decoder-enable`, `output-mode/processing_mode` (11 = virtualizzatore, 1 = no), `surround-boost` | 1,11,96 / 1,11,96 / 0,1,0 / 0,1,0 (**visto**) | interruttore + cursore 0-6 dB (96/16) a passi di 0,5 dB; massimo **ignoto** (si ipotizza 192 = 12 dB) |
| Dialoghi più chiari | `dialog-enhancer-enable`, `-amount` | 1,5 / 1,5 / 0,7 / 0,0 (**visto**) | interruttore + cursore 0-16 (scala Dolby, **dedotto**) |
| Volume uniforme | `volume-leveler-enable`, `-amount` (+ `in/out-target` -320 = -20 dB) | 0,5 / 0,5 / 0,2 / 0,0 (**visto**) | interruttore + cursore 0-10 (**dedotto**) |
| Equalizzatore | `ieq-enable`, `ieq-amount` (10), `ieq-bands-set` (preset), `graphic-equalizer-enable`, `-bands` (20 valori) | ieq 0 e geq 0 in tutti e quattro (**visto**) | menu Spento / Dettagliato / Bilanciato / Caldo / Personale; "Personale" mostra 10 cursori ±12 dB che pilotano coppie delle 20 bande (decisione 7) |
| Volume massimo | `volmax-boost` | 96 / 96 / 96 / 0 (**visto**) | interruttore "+6 dB" |
| Profilo Spento | profilo `off` (regolatore e PEQ altoparlanti restano attivi nella taratura, **visto** righe 331 e 392 di `windows-dolby-taratura.txt`) | | pulsante "Spento" |

Nota "Volume massimo" (**dedotto**): +6 dB davanti alla catena attuale, che ha già +12 dB di compressore e +6 dB
di ingresso del limitatore, porta più spesso il limitatore a lavorare; la catena dopo il motore protegge gli
altoparlanti, ma il suono può diventare più "schiacciato". Da ascoltare prima di decidere i valori.

### 5.5 Cuffie e altre uscite
- Nessuna presa jack gestita (**visto** UCM). Cuffie Bluetooth/USB = altri sink; la filter-chain manda solo agli
  altoparlanti (`target.object`, **visto**), quindi su quelle uscite oggi non c'è alcun effetto.
- La taratura ha solo l'endpoint `internal_speaker` (**visto**): nessun valore Dolby per le cuffie.
- Comportamento proposto: l'app osserva l'uscita predefinita (`pw-dump`/`wpctl status` letti dal servizio,
  oppure eventi del server Pulse con `pactl subscribe`); se non è "Altoparlanti potenziati" mostra
  "Uscita: <nome> - effetti attivi solo sugli altoparlanti" e disattiva i controlli. Il motore resta in pausa
  (il ponte non riceve audio). Effetti anche in cuffia = seconda catena da progettare (decisione 7).

---------------------------------------------------------------------------------------------------

## 6. Inserimento nel kit

### 6.1 File nuovi
```
K/audio-auto/dolby/10-integrazione-app.md      questo documento
K/audio-auto/dolby/app/...                     sezione 5.1
K/audio/50-yoga-altoparlanti.conf              MODIFICATO: un nodo in più in testa (vedi sotto)
K/pacchetti/...                                RPM per l'ospite, se servono (es. Wine): dagli altri agenti
```
Modifica della filter-chain (solo esempio, non applicata):
```
{ type = ladspa name = ponte plugin = yoga_ponte label = yoga_ponte
  control = { "Bypass" = 0.0 } }
...
links  = [ { output = "ponte:Out L" input = "hpL:In" } { output = "ponte:Out R" input = "hpR:In" } ... ]
inputs = [ "ponte:In L" "ponte:In R" ]
```
Se il file `yoga_ponte.so` manca, la filter-chain non parte (**dedotto**: un plugin mancante fa fallire il
grafo). Per questo `audio-sistema.sh` deve installare la versione con il ponte SOLO se il .so è stato copiato con
successo, altrimenti quella di oggi.

### 6.2 Cosa fa lo script di avvio (estensione di `avvio/audio-sistema.sh`, che accetta già la radice `$R`)
1. Copia `yoga_ponte.so` in `$R/usr/lib64/ladspa/` (come oggi `sc4_1882.so`).
2. Installa `50-yoga-altoparlanti.conf` con il ponte (o quella attuale se il passo 1 fallisce).
3. Copia app, servizio e taratura in `$R/usr/local/share/audio-yoga/` (o `/opt/audio-yoga`, decisione 7).
4. Copia `audio-yoga.desktop` in `$R/usr/share/applications/`, l'icona in
   `$R/usr/share/icons/hicolor/scalable/apps/`, e (se vassoio) `audio-yoga-vassoio.desktop` in `$R/etc/xdg/autostart/`.
5. Copia `audio-yoga-motore.service` in `$R/etc/systemd/user/` e aggiunge `Wants=audio-yoga-motore.service`
   al drop-in già esistente `default.target.d/10-yoga-audio.conf` (stesso metodo già usato per filter-chain,
   che evita i preset di systemd).
6. `restorecon` sulle nuove cartelle (già fatto per le altre nello script).
Nessun passo nuovo in `utente-login.sh`: l'uscita predefinita non cambia.

Unità del servizio (esempio): `After=pipewire.service`, `Restart=always`, `RestartSec=2`,
`ExecStart=/usr/bin/python3 /usr/local/share/audio-yoga/motore/controllo.py`; l'ospite è figlio del servizio
(o seconda unità con `PartOf=`), così se muore viene rilanciato e nel frattempo il ponte è in riserva.

### 6.3 Senza rete sul sistema installato
- Python 3, PySide6, gcc: presenti nella live (**visto**); dopo l'installazione da live, Anaconda copia
  l'immagine, quindi restano (**dedotto**; da verificare sul sistema installato).
- `yoga_ponte.so` compilato in anticipo e messo nel kit (non si compila all'avvio; `ladspa.h` non serve a runtime).
- Se si scegliesse la strada (a): servirebbe `pipewire-devel` o il binario già compilato nel kit.
- L'ospite e le sue dipendenze (DLL Dolby da `/mnt/win` o copia nel kit, eventuale Wine in `K/pacchetti`):
  **ignoto**, dagli altri compiti. Le DLL sono di Dolby/Lenovo: copiarle nel kit è una decisione (7).
- `avvio/dopo-anaconda.sh` è il punto naturale per applicare `audio-sistema.sh` con `$R` al sistema installato (**dedotto**: file presente, contenuto non
  riletto per questo compito).

---------------------------------------------------------------------------------------------------

## 7. Decisioni del proprietario
1. Nome definitivo dell'app e icona (qui "Audio Yoga" come nome di lavoro).
2. Strada di integrazione: plugin nella filter-chain (consigliata, d) o nodo separato (a).
3. Dimensione del blocco / latenza accettabile (5 ms, 10 ms) e se vietare quantum minori di B con
   `node.latency` (utile solo se si usano app audio a bassa latenza).
4. Icona nel vassoio con avvio automatico: sì/no.
5. Profili visibili: solo i 4 di Windows o anche Gioco/Voce presenti nella taratura.
6. Equalizzatore personale: 10 cursori (coppie di bande) o tutte le 20 bande; intervallo ±12 dB o altro.
7. Profilo "Spento": motore con profilo `off` della taratura (regolatore attivo) oppure ponte in diretto
   (nessuna elaborazione Dolby).
8. Volume massimo e compressore della catena attuale: lasciare +12 dB di compressore anche con il motore attivo o
   ridurlo quando il motore è attivo (va ascoltato).
9. Cuffie Bluetooth/USB: nessun effetto (proposta) o seconda catena dedicata.
10. Copia delle DLL Dolby e dell'XML nel kit (licenza) oppure lettura ogni volta da `/mnt/win`.
11. Dove installare l'app: `/usr/local/share/audio-yoga` o `/opt/audio-yoga`.

## 8. Ignoto (da provare quando ponte e ospite esistono)
- Quantum reale durante la riproduzione e latenza ALSA (serve far suonare qualcosa).
- Uso effettivo della porta "latency" di un plugin LADSPA da parte del filter-graph 1.6.9.
- Dimensione di blocco e latenza interna del motore; meccanismo di risveglio possibile per l'ospite.
- Intervalli massimi dei parametri Dolby (surround-boost, bande geq).
- Durata del buco audio quando systemd riavvia la filter-chain dopo un crash.
