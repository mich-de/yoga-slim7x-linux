# Audio Yoga: i profili audio di Windows su Fedora, con il codice Dolby originale del portatile

Documento di progetto, 17/11/2026. Stato: in attesa di approvazione. Basato sui dieci rapporti di studio
`01`…`10` di questa cartella (lettura statica: nulla è stato ancora eseguito).

## Perché
Il proprietario vuole su Fedora lo stesso suono e la stessa app di profili che ha in Windows, usando proprio
gli algoritmi Dolby del suo portatile e non equivalenti aperti.

## Che cosa si ottiene
- Su Fedora, su questo portatile, l'audio degli altoparlanti passa per il codice Dolby originale preso dal
  Windows del portatile, con la taratura Lenovo di questo modello.
- Un'app propria ("Audio Yoga", nome e grafica propri) per scegliere il profilo e regolare le funzioni.
- Tutto parte da solo all'avvio; se il motore manca o si guasta l'audio continua senza elaborazione.

## Fuori dal progetto
- Cuffie, Bluetooth, USB: nessuna elaborazione (in Windows usano un'altra taratura).
- Decodifica di contenuti Dolby Digital / Atmos: è un altro componente.
- Altri computer. Pubblicazione dei file Dolby. Marchio Dolby nell'app.
- Ritaratura della catena "Altoparlanti potenziati" e guadagno degli amplificatori (HANDOFF punto 21).

## Da non fare mai
- Modificare i file Dolby o aggirare controlli: i file restano identici (impronta verificata) e vengono solo
  caricati in memoria. Se una verifica di autenticità impedisse l'elaborazione, ci si ferma e si avvisa.
- Mettere il motore dopo la catena che protegge gli altoparlanti, o alzare guadagni in automatico.
- Lasciare l'utente senza audio.

## Fatti accertati dallo studio
- Sugli altoparlanti lavorano due DLL in serie, versione 3.30812.891.0: `DolbyAPOVR.dll` (contenuti: volume
  massimo, dialoghi, livellatore, equalizzatori, surround) e `DolbyAPOvlldp150.dll` (altoparlante:
  ottimizzatore a 20 bande, regolatore, compressore multibanda, limitatore). `DolbyDax3Apo.dll` smista soltanto.
- Dentro ogni DLL c'è una libreria in C con funzioni di creazione, impostazione dei parametri ed elaborazione
  di un blocco; lavora in virgola mobile, 48 kHz, blocchi di 256 campioni. Indirizzi nel rapporto `06`.
- I DLL di elaborazione non contengono controlli di licenza né di hardware e non usano rete o crittografia.
- Il servizio `DAX3API.exe` non tocca l'audio: traduce la taratura in parametri. Su Fedora non serve.
- La taratura del portatile ha 10 profili da 130 parametri (`taratura-yoga.json`); i nomi dei parametri
  coincidono con quelli della libreria. In Windows oggi è sempre attivo "Musica".
- Il progetto pubblico gemello (Surface Pro 11, licenza BSD-2) fa già girare questi due DLL su Linux ARM64
  dentro un plugin di PipeWire, con un caricatore di 113 righe, ma per un'altra versione dei DLL: gli
  indirizzi vanno ritrovati per la versione del Yoga.

## Strade considerate
| Strada | Pro | Contro |
|---|---|---|
| **A. Ponte nativo** (scelta): i due DLL caricati in memoria dentro un plugin di PipeWire, chiamando le funzioni della libreria Dolby | piccolo, senza rete, già provato dal gemello, ritardo basso (37 ms sul Surface) | indirizzi legati alla versione dei DLL; se Windows aggiorna il driver vanno ritrovati |
| B. Sotto Wine, come oggetti di Windows | usa i DLL tali e quali, senza indirizzi interni | Fedora non ha Wine per ARM64 (1,2 GB da Debian), processo separato e ponte verso PipeWire, difficile da tenere nel kit senza rete |
| C. Riscrivere gli algoritmi | nessun DLL a runtime | non sono più "gli algoritmi originali"; mesi di lavoro |

Scelta A perché soddisfa la richiesta (codice originale) con il minor peso; B resta come riferimento di
verifica se A non bastasse.

## Come è fatto
```
applicazioni
   |  uscita predefinita
[ Audio Yoga ]  filtro PipeWire in un servizio a parte, 2 canali 48 kHz
   |   plugin "ponte": DolbyAPOVR -> DolbyAPOvlldp150 (codice originale, blocchi da 256)
   |   se i DLL mancano, non corrispondono o il motore sbaglia: passaggio diretto
[ Altoparlanti potenziati ]  catena attuale: incrocio, correzione, limitatori
   |
DSP con protezione -> amplificatori -> altoparlanti

[ app Audio Yoga ] --socket--> [ servizio utente ] --pagina di controllo--> plugin
                                   stato in ~/.config/audio-yoga/stato.json
```
- **Ponte**: carica i due DLL all'indirizzo previsto, verifica l'impronta SHA-256 contro quelle note, crea le
  due librerie, applica i parametri del profilo chiamando le funzioni di impostazione, elabora a blocchi di
  256 con una coda che rende costante il ritardo. Gira in un servizio `filter-chain` separato, così un suo
  guasto non ferma la catena che protegge gli altoparlanti.
- **Profili**: letti da `taratura-yoga.json`; la sezione dei contenuti va a `DolbyAPOVR`, quella
  dell'altoparlante a `DolbyAPOvlldp150`.
- **File Dolby**: copiati dal Windows del portatile in una cartella privata della chiavetta e del sistema
  installato, mai nel repository pubblico (come già si fa per i firmware).
- **App** (PySide6, già presente): finestra come da schema approvato, icona nel vassoio, avvio automatico.
  Il servizio utente ripristina l'ultimo stato all'accesso anche senza aprire l'app.

## Proposte da confermare (decisioni del proprietario)
1. Profili mostrati: Dinamico, Film, Musica, Gioco, Voce, Spento (sei pulsanti su due righe invece dei quattro
   dello schema); predefinito Musica, come in Windows.
2. "Spento" = profilo `off` della taratura (resta il regolatore dell'altoparlante), non audio grezzo.
3. Equalizzatore personale a 20 bande (quelle della libreria), da −12 a +12 dB, con i tre preset della taratura.
4. Icona nel vassoio e avvio automatico: sì.
5. Nome di lavoro "Audio Yoga".

## Fasi e prove (ogni fase si chiude solo se la prova riesce)
1. **Ponte a file, solo altoparlante**: `DolbyAPOvlldp150` elabora un file WAV su Fedora senza suono.
   Prova: uscita ripetibile, senza valori non validi, e risposta in frequenza misurata uguale alla curva a
   20 bande del profilo (da −2 a +2,5 dB su Musica) entro 0,5 dB.
2. **Ponte a file, catena completa**: si aggiunge `DolbyAPOVR`. Prova: ogni funzione fa ciò che dice il suo
   parametro (per esempio +6 dB di volume massimo, bande dell'equalizzatore), profili diversi danno uscite
   diverse, "Spento" lascia solo il regolatore.
3. **Tempo reale**: plugin in PipeWire prima di "Altoparlanti potenziati". Prova: ritardo misurato, nessuna
   interruzione in dieci minuti, passaggio diretto quando si tolgono i DLL.
4. **App e servizio**: cambio di profilo e regolazioni dal vivo, stato ripristinato all'accesso.
5. **Kit**: installazione automatica dalla chiavetta e sul sistema installato, senza rete.
6. Facoltativa: confronto con registrazioni fatte in Windows sugli stessi file di prova.

## Rischi
- Gli indirizzi di `DolbyAPOVR` sono in parte dedotti per analogia: la fase 2 può richiedere altro studio.
- Alcune tabelle interne dei DLL sono riempite da Windows all'avvio e vanno preparate a mano (il gemello lo fa
  per le trasformate): vanno ritrovate nella versione del Yoga.
- La traduzione di alcuni parametri a più valori non è ancora certa: si verifica misurando.
- Un aggiornamento del driver Dolby in Windows cambia i DLL: il ponte li rifiuta e lascia passare l'audio
  finché gli indirizzi non vengono aggiornati.

## Lasciato a chi costruisce
Struttura dei sorgenti, formato della pagina di controllo, nomi dei file, dettagli dell'interfaccia entro lo
schema approvato. Riferimenti: rapporti `02` (interfaccia), `06` (indirizzi e parametri), `07` (taratura),
`08` (codice riusabile del gemello: `dolby-port/sp11_vlldp_pe_loader.h`, `sp11_dolby_windows_chain_ladspa.c`),
`10` (integrazione con PipeWire).
