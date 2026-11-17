# memory — progetto Linux su Yoga Slim 7x

## Fatti stabili
- Laptop: Lenovo Yoga Slim 7x 14Q8X9 (83ED), Snapdragon X Elite X1E78100, Windows 11 ARM64, BIOS NHCN62WW.
- **Tastiera + touchpad**: funzionano in Linux solo con il bus I2C `/soc@0/geniqup@bc0000/i2c@b80000` a 100 kHz (il device tree ufficiale lo mette a 400 kHz: dati corrotti, SDA bloccata, errori -110). Rimedio provato a caldo il 16/11; avvio a freddo da confermare.
- **Audio**: scheda funzionante nella live; volume basso perché i tweeter restano muti con lo stereo e `PA Volume` degli amplificatori WSA884x è inerte. Rimedi: `6-AUDIO-PIU-FORTE.sh`, `7-VOLUME-AMPLIFICATORI.sh`. Nessuna protezione altoparlanti in Linux.
- Chiavetta: Transcend TS256GSS (adattatore JMicron): p1 ISO Fedora 45 KDE aarch64 raw (kernel 7.2.11-300.fc45), p2 ESP (menu GRUB), p3 STRUMENTI (Y: in Windows) = kit completo, indice `LEGGIMI.txt`.
- BIOS: solo Secure Boot on/off, Reset to Setup Mode, Restore Factory Keys. Stato: Setup Mode, chiavi vuote, Secure Boot off.
- Shim Fedora 45 firmato Microsoft UEFI CA 2023; Windows ha `DBUpdate3P2023.bin` per aggiungerlo al db.
- Secure Boot attivo è incompatibile con la correzione tastiera attuale (kernel modificato / moduli non firmati).
- I moduli `i2cslow2.ko` e `wsagain.ko` valgono solo per il kernel 7.2.11-300.fc45.
- WSL Ubuntu 26.04 arm64 su Windows: utile per collaudare script e manipolare ISO/DTB (lanciare da PowerShell con script su file).

## Decisioni
- Distro: Fedora 45 KDE Plasma aarch64, chiavetta raw (niente Ventoy).
- Voce GRUB predefinita: kernel con il device tree interno corretto a 100 kHz (`boot/linux-7.2.11-300.fc45-kbd100k.efi`).
- Segnalazione/patch upstream e aumento dei guadagni audio: solo con decisione esplicita dell'utente.

## Vincoli e regole
- Più sessioni (Windows e live Fedora) scrivono sulla stessa chiavetta: **prima di scrivere, elencare ESP e STRUMENTI e non sovrascrivere file altrui** (il 16/11 sera è stato fatto senza guardare: vedi HANDOFF §6).
- Confermare prima di scritture nel firmware, cancellazioni, elevazioni (UAC disabilitato).
- Controllare BitLocker (`manage-bde -status C:`) prima di ogni modifica Secure Boot.
- Mai `systemd.run=` nel cmdline. Non toccare il GPIO 65 (reset dell'EC).

## Aggiunte del 16/11 sera
- Richiesta esplicita dell'utente: **tutto automatico e integrato nella chiavetta, senza rete e senza comandi da lanciare**.
- Voce GRUB predefinita "TUTTO AUTOMATICO": kernel corretto + `strumenti.cpio` (cartella `/updates` applicata dalla live) + `enforcing=0`. Logica in `STRUMENTI/avvio/` (autorun-root, audio-sistema, audio-ampli, utente-login, dopo-anaconda).
- Systemd al primo avvio applica i preset di Fedora e rimuove i symlink in `*.wants`: attivare i servizi con drop-in `Wants=`.
- Anaconda esegue i `*.ks` di `/usr/share/anaconda/post-scripts`: usato per preparare da solo il sistema installato.
- Audio non può essere "come Windows 11": lì c'è Dolby Atmos (taratura del modello in `audio-auto/windows-dolby-taratura.txt`).
- Prove possibili da Windows: QEMU in WSL con l'immagine `D:\linux\_vm\stick.img` (Fedora vera, non l'hardware).

- Audio Windows: la taratura Lenovo degli altoparlanti sta nel modulo DSP 0x0701000B, parametro 0x0800137B (incrocio 2400 Hz); il sottografo 0xB0000003 non è la catena della musica.
- Righe rosse all avvio della live (cdsp_dtbs.elf, pmic_glink, gen70500_sqe.fw, qcom-apm CMD timeout): innocue.

- Tastiera e touch confermati dall utente sul portatile (prima voce del menu, 16/11).
- Webcam: sensore OV02C10; driver presenti nel kernel Fedora 7.2.11, manca il device tree (camcc, cci, camss, sensore). Riferimento funzionante: aruhier/linux-slim7x-x1e.
- D: decifrato il 16/11 (NTFS in chiaro); C: resta BitLocker con chiave in chiaro.

- Volume basso su Linux: voluto dal kernel (niente protezione altoparlanti). `PA Volume` v = 21 − 1,5×(31 − v) dB, letto solo alla ripartenza dell'uscita, tetto 6 nel driver della scheda (`wsagain cap=N` lo alza), UCM lo rimette a 12. Guadagno pieno = +24 dB rispetto al default. Alzarlo è decisione dell'utente.
- Altoparlanti: canali PCM 0,1 woofer (nulla sotto 250 Hz), 2,3 tweeter (19 dB più sensibili a 2 kHz). Catena tarata con `tools/misura-audio.py`: incrocio 2400 Hz, tweeter −7 dB non invertiti. I microfoni interni non sono affidabili sopra 8 kHz.
- Webcam a caldo: il kernel live ha `OF_OVERLAY` e `__symbols__`; mancano nel DT anche i regolatori della camera, non solo camcc/cci/camss.
- Nella live: `echo | sudo -S -p '' comando`; controlli ALSA per numid.

- Protezione altoparlanti (Windows): un solo modulo SP_RX `0x411A` e un SP_VI `0x4121` per 4 altoparlanti, ritorno V/I a 8000 Hz / 32 bit / 4 canali su LPAIF WSA indice 1; R0/T0 nel registro (`Services\qcadcm\State\SpeakerProtectionInfo`). File pronto: `audio/protezione/yoga-slim7x-spkr-prot.bin`.
- Linux 7.2.11 non ha control link né invio di tarature in `audioreach.c`: la protezione richiede `snd-q6apm` modificato, topologia nuova e il ritorno V/I nel device tree. Progetto di riferimento: `geocausa/SP11X1e-audio`.
- Decisione dell'utente: guadagno pieno solo con protezione provata dalla telemetria.
- Protezione altoparlanti su Linux (17/11): lato DSP provato (topologia + `snd-q6apm-sp` + tarature: 45/45 frame accettati). Senza ritorno V/I SP_RX lascia passare il suono invariato: non protegge. Indicatore per il ritorno V/I: stato di calibrazione `0x4121 0x080011F8` (1 fermo, 7 attesa scaduta, 4 riuscita). File in `repo/strumenti/audio/protezione/`.
- Il kernel chiede la topologia come `qcom/x1e80100/<modello>-tplg.bin`; i file in `/lib/firmware/updates/` hanno la precedenza.
- `apr.c` 7.2.11: sganciare un driver GPR toglie la porta del servizio e lascia la callback vecchia: mai riagganciare un driver senza `gprport.ko`; mai scaricare `snd_q6apm` di serie (lo usa `q6prm`).
- Convenzione: i moduli fuori albero si costruiscono con `make BUILD=cartella` (sorgenti scaricati da git.kernel.org per la versione esatta + patch), mai con cancellazioni nel Makefile.
- Ritorno V/I SoundWire (17/11): si apre da un modulo d'aiuto con l'API del bus (`sdw_stream_add_slave/master`, prepare, enable), senza DAI ne' device tree; direzione RX nello stream (solo contabilita' del core). La scheda di serie non puo' farlo: `qcom_swrm_stream_alloc_ports` rifiuta le porte 10/11. Ordine di Windows: prima gli amplificatori accesi, poi i clock V/I delle macro.
- Ritorno V/I, prova del 17/11 mattina: con `wsavi` il DSP riceve i segnali (stato 3), ma la calibrazione fallisce (stato 5, R0 2,025 ohm su un solo canale).
- Live: Fedora non carica `scmi-cpufreq` da solo e il CDSP non parte (manca `cdsp_dtbs.elf`); dal 17/11 li sistema `avvio/autorun-root.sh` (sul sistema installato: `dopo-anaconda.sh`); il CDSP parte gia' dall'initramfs perche' `strumenti.cpio` contiene i due firmware in `usr/lib/firmware/updates/`.
- `strumenti.cpio`: mai voci `lib/...` (nell'initramfs `lib` e' un collegamento a `usr/lib` e verrebbe cancellato); si rifa' con `chiavetta-efi/mk_cpio.py initrd strumenti.cpio`; quello attivo e' `/strumenti.cpio` sulla ESP.
- Messaggi d'avvio di serie e innocui (oltre a quelli sopra): `dracut-crypt-generator` exit 2, MODSIGN/integrity, `snd-seq not found`, ciclo `kde-baloo`, powerdevil DDC, stratis, smartd, alsactl. Elenco ragionato: HANDOFF §20.
- Nella live, per scrivere in sysfs da root: `sudo sh -c 'echo x > file'` (con `echo | sudo -S` lo stdin di `tee` va perso).
- Dopo `scambia.sh` il volume torna al tetto di serie: rilanciare `avvio/audio-ampli.sh`.

## Protezione altoparlanti: fatti del 17/11 (reverse del driver Windows)
- Windows tiene gli amplificatori a **18 dB** (selettore `0x24` nell'ACDB), non 21, con profilo per carico 4 Ω: `ISENSE2 0x3021 = 0x07`, `VSENSE1 0x3020 = 0x67`. Linux lascia `0x27`/`0x87` e li riscrive a ogni accensione dell'altoparlante. Profilo completo: `audio/protezione/amplificatori/`.
- Controller SoundWire Qualcomm: `Offset2 + 1` = distanza fra i canali di una porta. Le porte 10/11 (ritorno V/I) vogliono `Offset2 = 0`; il device tree ha `0xff` e allora V = I. Una resistenza letta di circa **2,02 Ω** è il segno di V e I uguali (15,07/7,01 − 0,13).
- La taratura di SP_VI presume l'amplificatore a 18 dB: pilota −40 dBFS (0,110 V di picco atteso), soglia 25 %, attesa V/I 100 ms, R0 accettato fra 1/1,5 e 1,5 volte il tipico. Sotto circa 6 dB di guadagno il pilota non viene visto (stato 7): calibrazione e protezione si provano solo con `PA Volume` vicino a 29.
- Stati di calibrazione: 6 = in attesa di V/I, 7 = attesa scaduta, 8 = V/I bassi.
- Il progetto gemello `geocausa/SP11X1e-audio` ha già risolto gli stessi passi (documenti del 20/08: Offset2, ordine PA → clock di protezione): leggerlo prima di provare.
- SnapControl su Linux: `/run/media/liveuser/Volume/snapcontrol` (minuscolo). Profili colore del pannello copiati in `repo/strumenti/schermo/profili/`.
- **Protezione provata il 17/11** (a 18 dB, con `wsavi`): calibrazione 3,840 / 3,594 / 4,218 / 3,983 Ω (Windows 3,883 / 3,640 / 4,252 / 4,007); il controllo termico di SP_RX attenua fino a 12 dB e segue la temperatura misurata dal ritorno V/I. Limite vero: `temp_tgt_q6` = 90 °C nel parametro `0x08001532` di SP_RX (non `0x08001510`). Senza V/I il DSP presume 50 °C. Le statistiche del DSP (`0x080011EF`…`F2`) non si leggono su questo firmware.
- A 18 dB l'uscita è +22 dB rispetto al guadagno minimo di Linux. Script: `kernel/prova-vi-18db.sh`, `kernel/prova-protezione.sh` (ripristinano da soli `PA Volume` 18/16).
- Consenso dell'utente del 17/11: solo per le prove a 18 dB fatte (silenzio; toni fino a −20 dBFS). Livelli più alti e uso quotidiano a 18 dB vanno chiesti.
- `HANDOFF.md` contiene byte che `grep` tratta come binari: cercare con `awk` o `python`.

## App audio con il codice Dolby originale (dal 17/11)
- Decisioni dell'utente: app su misura "Audio Yoga" (PySide6, sei profili, Musica predefinito), motore = DLL Dolby originali del suo Windows caricati così come sono; a app finita pubblicare su GitHub (`origin` = `mich-de/yoga-slim7x-linux`) senza file Dolby né altri file proprietari o personali.
- Il codice di `DolbyAPOvlldp150.dll` (3.30812.891.0) gira su Fedora ARM64 caricato da `repo/strumenti/audio/dolby/pe.c`: serve x18 puntato a un blocco fittizio e le sezioni critiche di Windows collegate a funzioni vuote; nessun'altra funzione di Windows viene chiamata. L'interruttore a stato+0xC6C va messo a 1 o l'uscita è muta.
- I valori dei parametri nel registro di Windows coincidono con l'XML di taratura; in Windows è attivo sempre il profilo Musica.
- Progetto, piano e rapporti: `repo/strumenti/audio-auto/dolby/` (`PROGETTO.md`, `PIANO-1-motore-a-file.md`, `01`…`10`).
- **Audio Yoga versione 1 (17/11)**: uscita PipeWire "Audio Yoga" prima di "Altoparlanti potenziati", servizio utente `audio-yoga.service`, app `/usr/local/bin/audio-yoga`, installazione `avvio/audio-yoga.sh`, file privati in `STRUMENTI/dolby-privato/`. Comando dal vivo: `pw-cli set-param <id di effect_input.audio_yoga> Props '{ params = [ "dolby:Profilo" 2 ] }'` (0 Dinamico … 5 Spento; `dolby:Spinta`; `dolby:EQ 1`…`20`).
- Il servizio dei filtri di serie di Fedora ha `MemoryDenyWriteExecute=yes`: il motore gira in un servizio suo.
- In una cartella con `nome.so` e `nome.py`, `import nome` di Python prende il `.so`: caricare per percorso.
- `pkill -f` con un testo che compare nel proprio comando uccide la shell che lo lancia.
- **Audio Yoga completo (17/11)**: anche `DolbyAPOVR.dll` gira su Fedora (surround virtuale, dialoghi, livellatore); sul Yoga il surround vale anche per l'audio stereo. Nel profilo Musica il secondo DLL è trasparente. Comandi del filtro: `dolby:Surround`, `dolby:Dialoghi`, `dolby:Livellatore` (−1 = come il profilo).
- GitHub: repository privato `mich-de/yoga-slim7x-linux`; nella live `gh` non è autenticato (serve `gh auth login -h github.com`); i lavori si committano su un ramo, non su `main`.
- Mai `pkill -f testo` quando lo stesso testo compare nel comando che si sta lanciando: usare `pgrep -a nome | awk` e `kill`.
- Audio Yoga non esce su "Altoparlanti potenziati" ma su una copia senza compressore, "Altoparlanti (via Audio Yoga)" (`effect_input.yoga_spk_ay`, generata da `avvio/audio-yoga.sh`): il compressore 3:1 e i +18 dB della catena originale appiattivano ogni differenza (quattro profili entro 0,4 dB all'uscita finale, misurato il 17/11).
- Per verificare un effetto audio si misura all'uscita finale (`alsa_output.platform-sound.HiFi__Speaker__sink`, 4 canali), non solo all'uscita del filtro. Le registrazioni a 4 canali di `pw-record` sono WAV "extensible": il modulo `wave` di Python non le legge, si cerca il blocco `data` a mano.
