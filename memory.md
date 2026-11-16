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
