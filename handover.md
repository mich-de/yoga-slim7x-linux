# handover

Stato completo: `HANDOFF.md` (stessa cartella, copia su Y: e sulla ESP). Fatti stabili: `memory.md`.
Testo della sessione live recuperato: `HANDOFF-sessione-live-16.30-recuperato.md`.

- Fatto: chiavetta resa automatica (voce predefinita: tastiera/touchpad nel kernel, audio e diagnostica da servizio iniettato, preparazione automatica del sistema installato a fine installazione); kit STRUMENTI aggiornato su Y:; catena di avvio e script provati su Fedora 45 in macchina virtuale.
- Resta: avvio a freddo sul portatile (tastiera, touchpad, audio reali), installazione vera di Fedora, decisione su Secure Boot, invio upstream (solo con approvazione).
- Aperto: rigenerazione initramfs di `dopo-anaconda.sh` non conclusa in emulazione (troppo lenta); audio non equivalente a Windows (Dolby); modifiche della sessione live a LEGGIMI e script 1–4 perse nella sovrascrittura del pomeriggio.

## 16/11 notte
Primo avvio reale riuscito (desktop, driver della tastiera, touch multitocco, audio configurato). Mancano: conferma su tasti e suono, riduzione di D: (in attesa di conferma), installazione. Seconda passata di reverse fatta: HANDOFF.md punto 11.
Esito utente: tastiera e touch OK, audio non come Windows, webcam non funziona (causa e strade: HANDOFF.md punto 12).

## 16/11 ore 23, dalla live Fedora
Audio: trovata e corretta la causa del suono cupo (buco a 2 kHz, acuti bassi); nuova catena PipeWire attiva e nel kit, misurata (scarto 3,4 → 1,8 dB). `PA Volume` e compander: senza effetto. Manca il giudizio a orecchio dell'utente.
Webcam: solo fattibilità (overlay a caldo possibile; mancano camcc, cci, camss, sensore e regolatori). Prossimo passo: scrivere l'overlay. Dettagli: HANDOFF.md punto 15.
Resta: installazione di Fedora (riduzione di D: da confermare), commit e push (da confermare).
Volume basso: causa trovata (il kernel tiene gli amplificatori al minimo, 24 dB sotto il massimo, perché manca la protezione). Decisione dell'utente: niente aumento senza protezione; attivare la protezione del DSP con i parametri di Windows e poi +24 dB. Piano e fatti: HANDOFF.md punto 16.

## 16/11 notte, sessione "protezione audio"
Reverse della protezione altoparlanti chiuso: grafo di Windows, tarature a 4 altoparlanti, R0/T0 del portatile, file per il DSP generato e verificato. Resta lo sviluppo: topologia con SP_RX/SP_VI, `snd-q6apm` fuori albero (control link + invio tarature), ritorno V/I dall'hardware, prove con telemetria. Nessun guadagno alzato. Dettagli e piano: HANDOFF.md punto 17.

## 17/11 notte, sessione "protezione audio, punto 17"
Fatto: topologia con SP_RX/SP_VI, `snd-q6apm` modificato (control link, tarature da file, `getcfg`), scambio a caldo. Sul portatile: grafo aperto, 45 frame accettati su 45, configurazione riletta dal DSP; in calibrazione lo stato arriva a 7 (attesa V/I scaduta) appena si accende il percorso V/I delle macro. Manca il trasporto SoundWire dei segnali V/I dagli amplificatori: è il prossimo lavoro. Nessun guadagno alzato.
Problema aperto: l'audio di questa live è fermo fino al riavvio (Oops causato dal percorso `off` dello scambio; corretto in `gprport.c`, non riprovato). Dettagli e passi: HANDOFF.md punto 18.

## 17/11 ore 00:40, sessione "ritorno V/I"
Fatto: `wsavi.ko` ora apre il flusso SoundWire V/I (porta 5 dei 4 amplificatori verso le porte 10/11 dei due controller) oltre al percorso delle macro; provato sul portatile senza DSP (nessun errore, 15 s senza collisioni). Pronti `prova-vi.sh` e `statovi.py`. Resta: riavviare la live (audio ancora fermo) e lanciare `sudo bash repo/strumenti/audio/protezione/kernel/prova-vi.sh`; atteso stato 4 e R0 di 3,6-4,3 ohm. Nessun guadagno alzato. Dettagli e alternative se fallisce: HANDOFF.md punto 19.

## 17/11 mattina, sessione "prova V/I ed errori dell'avvio"
Prova V/I fatta: non piu' attesa scaduta; stato 3 poi 5 (fallita), R0 2,025 ohm su un solo altoparlante. I segnali arrivano al DSP, la calibrazione no. Prossimo: `prova-vi.sh 1` e alternative del punto 19.
Errori dell'avvio: corretti filesystem di STRUMENTI (fsck, nessun danno), regolazione della frequenza CPU nella live (`scmi-cpufreq`), CDSP (firmware del kit + avvio); gli altri messaggi sono di serie e innocui. Modifiche in `avvio/autorun-root.sh`, provate a mano. CDSP corretto anche alla fonte: `strumenti.cpio` (ESP) ora porta nell'initramfs `qccdsp8380.mbn` e `cdsp_dtbs.elf`; vecchio cpio in `strumenti.cpio.bak-1711`. **Da fare subito dopo il riavvio: la verifica del punto 20, "Prossimi passi" 1** (nessun avvio vero fatto ancora con queste modifiche). Dettagli: HANDOFF.md punto 20.
Stato della live: driver con protezione attivo, volume e uscita potenziata come all'avvio. Nessun guadagno alzato.

## 17/11 mattina, sessione "audio come Windows, metodo nuovo"
Trovate con il reverse del driver Windows le due cause della calibrazione fallita: (1) `Offset2 = 0xff` sulle porte V/I del controller (V e I letti nello stesso bit: da lì i 2,02 Ω); (2) tono pilota sotto soglia perché la taratura presume l'amplificatore a 18 dB. Corrette nel modulo `wsavi` la prima e i sensori degli amplificatori; la seconda richiede una calibrazione a 18 dB con solo silenzio, da fare con il sì dell'utente. Windows usa 18 dB, non 21. Nel repo: profilo degli amplificatori e profili colore dello schermo (da snapcontrol). Nessun guadagno alzato. Dettagli e passi: HANDOFF.md punto 21.
Aggiornamento ore 9:50: con il consenso dell'utente, prove a 18 dB riuscite. Calibrazione del DSP: stato 4, resistenze entro l'1,3 % da Windows. Protezione termica: interviene (fino a 12 dB) e usa la temperatura misurata dal ritorno V/I. Guadagni rimessi a 18/16 dopo ogni prova. Restano: profilo di Windows dello stadio di potenza, salita oltre −20 dBFS, servizio per l'uso quotidiano (wsavi quando l'uscita parte), `Offset2` nel device tree, catena PipeWire da ritarare. HANDOFF.md punto 21.

## 17/11 ore 12:20, sessione "Audio Yoga"
Fatto: studio con 10 agenti, progetto approvato, e la versione 1 dell'app funziona. Il codice Dolby originale dell'altoparlante gira dentro PipeWire (uscita "Audio Yoga", predefinita in questa live), con sei profili, equalizzatore a 20 bande e volume massimo; app aperta, tutto nel kit. Mancano gli effetti del secondo DLL (surround, dialoghi, livellatore), la verifica con un avvio a freddo e la pubblicazione su GitHub (da fare ad app completa, senza file Dolby né dati privati). Dettagli: HANDOFF.md punto 22; sorgenti in `repo/strumenti/audio/dolby/`.
Aggiornamento ore 13:00: Audio Yoga è completo. Anche il secondo DLL Dolby (surround virtuale, dialoghi, volume uniforme) gira su Fedora ed è comandato dall'app; tutte le prove passano; chiavetta aggiornata. Commit pronto sul ramo `audio-yoga`; il push su GitHub aspetta `gh auth login` (token scaduto). Restano il riavvio di verifica e il giudizio a orecchio.
