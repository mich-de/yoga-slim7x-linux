# HANDOFF — Linux sul Lenovo Yoga Slim 7x (aggiornato 2026-11-16, ore 20)

Copie: `D:\linux\HANDOFF.md` (Windows), radice della partizione STRUMENTI (Y: in Windows) e ESP della chiavetta.
Questo file unisce due sessioni: quella su Windows (kit, firmware, Secure Boot) e quella fatta dalla live Fedora
il 16/11 pomeriggio (tastiera e audio). Il testo originale della sessione live, recuperato, è in
`HANDOFF-sessione-live-16.30-recuperato.md`.

## 1. Obiettivo
Fedora 45 KDE Plasma aarch64 in dual boot con Windows, tastiera e audio a posto; kit STRUMENTI completo per Fedora e altre distro; alla fine, se possibile, Secure Boot attivo.

## 2. Hardware e stato
- Lenovo Yoga Slim 7x 14Q8X9 (83ED), Snapdragon X Elite X1E78100, 32 GB, BIOS **NHCN62WW** (12/02/2025), Windows 11 ARM64.
- Interno: Samsung NVMe 1 TB (C: Windows, BitLocker con protezione disattivata; D: dati). Solo partizioni Windows: **Fedora non è ancora installata**.
- Chiavetta: Transcend TS256GSS 256 GB in adattatore JMicron 152D:0567 (non usare l'ASMedia 174C:55AA: reset UAS).
  - p1 ISO Fedora-KDE-Desktop-Live-45-1.4 aarch64 scritta raw (kernel 7.2.11-300.fc45).
  - p2 ESP FAT 30 MB (offset 3508396032): `EFI/BOOT/grub.cfg` (menu), `grub.cfg.orig`, `grub.cfg.bak-1530`, `grub.cfg.bak-1600`, `EFI/BOOT/yoga7x-kbd100k.dtb`, `/strumenti.cpio`.
  - p3 **STRUMENTI** FAT32 4 GB (offset 3539992576) = Y:. Indice: `LEGGIMI.txt`.
- Firmware UEFI: Secure Boot **Disabled**, Setup Mode, PK/KEK/db vuoti. Ritorno: BIOS > Security > Restore Factory Keys.

## 3. Tastiera + touchpad — causa trovata, rimedio provato a caldo
- **Causa** (sessione live): il controller tastiera ITE 048D:8987 (I2C 0x3a, bus `b80000.i2c`, condiviso col touchpad ELAN 04F3:3303 a 0x2c) con questo BIOS **non regge i 400 kHz** del device tree ufficiale: descrittore HID corrotto dopo 16 byte, il driver scrive su un registro sbagliato, la tastiera tiene SDA bassa e blocca tutto il bus (errori `-110`, `failed to change power setting`). Il touchpad muore pochi secondi dopo l'avvio.
- **Rimedio**: `clock-frequency = <100000>` su `/soc@0/geniqup@bc0000/i2c@b80000`. **Confermato dall'utente a caldo** (tastiera scrive, touchpad va). Avvio a freddo: **da confermare**.
- Strumenti:
  - `5-FIX-TASTIERA-SUBITO.sh`: a caldo (modulo `fix-tastiera/i2cslow2.ko`, solo kernel 7.2.11-300.fc45; sblocco bus con gpioset; rebind `geni_i2c`).
  - `boot/linux-7.2.11-300.fc45-kbd100k.efi`: kernel della ISO con il device tree interno corretto (3 byte diversi dall'originale; DTB interno identico byte per byte a `fix-tastiera/yoga7x-kbd100k.dtb`). sha256 `4c735c178e0073a8242b083c9e6d63b8f6fa3d2c69191461021d2ec60a750070`. Voce GRUB predefinita.
  - `tools/patch-dtb-i2c100k.py`: corregge qualsiasi kernel con device tree incorporati o file .dtb.
  - `12-TASTIERA-FIX-PERMANENTE.sh`: corregge i kernel in /boot del sistema installato e installa l'aggancio `/etc/kernel/install.d/99-yoga-kbd100k.install`; `--dalla-live` per farlo subito dopo l'installazione, prima di riavviare.
  - `upstream/`: segnalazione per linux-arm-msm e patch RFC (firma OdissREA). **Non inviate**: mai senza approvazione dell'utente; prima confermare l'avvio a freddo, se possibile provare 200 kHz.
- I vecchi esiti "FUNZIONA" e "[OK] Tastiera" (file `esito-*`, `riepilogo-2026*` nella radice di Y:) erano falsi positivi (tastiera Bluetooth iClever). Le ipotesi hid_lenovo / rebind / sospensione erano sbagliate: script relativi in `vecchi/`.
- Con Secure Boot attivo nessuna di queste correzioni è utilizzabile (kernel modificato non firmato, `devicetree` di GRUB bloccato, moduli non firmati): vedi `secureboot/LEGGIMI.txt`.

## 4. Audio — funziona nella live, problema = volume
- Nella live l'ADSP risulta in esecuzione e la scheda audio c'è (anche con `modprobe.blacklist=qcom_q6v5_pas` nel cmdline).
- Scoperte della sessione live (misure con i microfoni interni): nel PCM a 4 canali 0,1 = woofer, 2,3 = tweeter → con lo stereo i tweeter restano muti; il controllo `PA Volume` degli amplificatori WSA884x è inerte perché il driver non imposta `CSR_GAIN_EN` (DRE_CTL_1 bit 0).
- Rimedi: `6-AUDIO-PIU-FORTE.sh` (sink PipeWire "Altoparlanti potenziati": passa-alto, compressore, limitatore, crossover 3 kHz verso i tweeter; serve `ladspa-swh-plugins`; file `audio/50-yoga-altoparlanti.conf`) e `7-VOLUME-AMPLIFICATORI.sh` (modulo `audio/wsagain.ko` con `en=0 cap=18`, PA Volume woofer 18 / tweeter 16, WirePlumber soft-mixer `audio/51-…conf`, amplificatori sempre accesi). Solo kernel 7.2.11-300.fc45; altrimenti ricompilare `audio/wsagain.c`. **Nessuna protezione altoparlanti in Linux: non aumentare quei valori.**
- Dopo l'installazione, se la scheda audio non compare: `11-AUDIO-BASE-FEDORA.sh` (blacklist ADSP, firmware, UCM, PipeWire). Poi 6 e 7.
- In `audio/windows/` ci sono calibrazione e XML presi da Windows; in `audio/windows-driver/` i pacchetti driver audio completi copiati da Windows (per studiare la protezione altoparlanti).
- Dalla diagnostica della live: CDSP offline (manca `cdsp_dtbs.elf` in Fedora: lo installa `8-INSTALLA-FIRMWARE.sh`), webcam e TPM non supportati, scmi-cpufreq da caricare (lo fa lo script 10).

## 5. Menu GRUB e automazione (richiesta dell'utente: "tutto automatico, integrato, senza rete, non voglio fare nulla")
Voci: 1. **TUTTO AUTOMATICO** (predefinita: kernel corretto + `strumenti.cpio` + `enforcing=0`). 2. solo FIX TASTIERA. 3. FIX TASTIERA con `devicetree` esterno (potrebbe non avere effetto). 4. senza fix. 5. automatico con messaggi visibili. 6. originale ISO.
- Parametri sempre per esteso: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0 modprobe.blacklist=qcom_q6v5_pas`. **Mai `systemd.run=`**.
- Tastiera/touchpad: la correzione è dentro il kernel caricato da GRUB (`STRUMENTI/boot/linux-…-kbd100k.efi`): nessuno script, nessuna rete.
- `strumenti.cpio` (cartella `/updates`, applicata dall'hook dracut `20-apply-live-updates.sh`) inietta nella live: `strumenti.service` + drop-in `multi-user.target.d/10-strumenti.conf`; `/usr/local/bin/strumenti-{mount,utente,menu}`; autostart `yoga-audio.desktop`; post-script Anaconda `/usr/share/anaconda/post-scripts/90-yoga-slim7x.ks`. Logica su STRUMENTI in `avvio/`:
  - `autorun-root.sh` (root, all'avvio): `audio-sistema.sh` (plugin LADSPA da `audio-auto/ladspa`, conf PipeWire/WirePlumber di `audio/`, filter-chain per tutti gli utenti via drop-in), `audio-ampli.sh` (logica e valori di `7-VOLUME-AMPLIFICATORI.sh`: wsagain `en=0 cap=18`, woofer 18, tweeter 16), poi diagnostica in `log/`.
  - `utente-login.sh` (utente): rende predefinita l'uscita "Altoparlanti potenziati".
  - `dopo-anaconda.sh` (a fine installazione, da Anaconda): copia il kit in `/opt/yoga-slim7x`, corregge kernel e dtb in `/boot` + aggancio `kernel-install`, audio di sistema + `yoga-audio-ampli.service` (drop-in), firmware, passi della guida Fedora (grubby, scmi-cpufreq, dracut), `restorecon`.
- **Scoperta in macchina virtuale**: al primo avvio systemd applica i preset di Fedora e **rimuove i collegamenti in `*.wants`** creati a mano → servizi attivati sempre con drop-in `Wants=` (mai con symlink).
- Nella live mancano: `gpioset` (lo script 5 vuole la rete), tastiera virtuale maliit, `qdbus`, plugin LADSPA (ora forniti dal kit).

## 5b. Prove in macchina virtuale (QEMU in WSL, Fedora 45 vera, NON l'hardware del portatile)
Immagine `D:\linux\_vm\stick.img` (copia sparse della chiavetta), script in scratchpad `vm/`. QEMU e erofsfuse installati in WSL (`apt remove qemu-system-arm qemu-efi-aarch64 erofsfuse erofs-utils` per toglierli).
Verificato: GRUB legge il menu, trova e avvia il kernel corretto dalla partizione STRUMENTI; l'initrd aggiuntivo viene applicato; `strumenti.service` parte; `audio-sistema.sh` installa tutto senza rete; diagnostica salvata; script 8, 9, 10, 12 e `dopo-anaconda.sh` girano su Fedora (patch di kernel e dtb, aggancio, grubby). Non concluso in emulazione: rigenerazione initramfs (troppo lenta). **Non verificabile in VM**: tastiera, touchpad e audio reali.

## 5c. Reverse dell'audio di Windows (obiettivo utente: "audio come in Windows", skill leanrea) — prima passata
Rapporto completo: `STRUMENTI/audio-auto/REVERSE-AUDIO-WINDOWS.md`; script ripetibili in `tools/re-audio/` (parser ACDB scritto a partire dai sorgenti pubblici AudioReach).
- Dolby DAX3 (profilo "dynamic" di questo modello, `SUBSYS_IDEA4001`): **nessuna equalizzazione fissa**; attivi virtualizzatore surround (altoparlanti a 10°), enfasi dialoghi, livellatore DRC, regolatore a 20 bande, volmax +6 dB. Algoritmi proprietari.
- DSP Qualcomm (da `acdb_cal.acdb`, 180 sottografi, 3486 parametri): catena altoparlanti GAIN (+3 dB) → MSIIR ×3 (l'EQ a 5 biquad esiste ma il modulo è **disattivato**) → IIR_MBDRC (1 banda + limitatore, attivo) → modulo ignoto `0x070010A3` → VOL_CTRL → SAL (limitatore, soglia ≈ −3 dBFS) → **SPEAKER_PROTECTION con ritorno V/I**.
- Conclusione: Windows non è "più bello" per un'equalizzazione copiabile; lo è per Dolby (spazialità) e per la protezione degli altoparlanti (volume senza rischi). Su Linux: parità non raggiungibile oggi; la strada utile è attivare la protezione del DSP con i parametri dell'ACDB e, per la spazialità, un virtualizzatore libero da tarare con misure.
- Da fare (serve Linux sul portatile, con misure ai microfoni): decodifica completa di IIR_MBDRC e dei parametri di protezione, significato delle chiavi CKV, identità di `0x070010A3`, confronto misurato Windows/Linux.
- Verificato: la topologia audio Linux del modello (e il suo sorgente a monte) non contiene SPEAKER_PROTECTION né compressore/limitatore; il driver del kernel (udioreach.c) supporta i moduli di protezione. Compressore DSP di Windows decodificato: 5:1, soglia ≈ −12 dBFS (dedotta), limitatore −3,1 dBFS, nessun recupero. Moduli  x070010A3 e simili non identificabili da fonti pubbliche.
- Regola dell'utente: per il reverse il modello previsto è Opus 4.6 medium (questa sessione era su Fable 5.2 per scelta dell'utente).

## 6. Errore della sessione Windows del 16/11 sera (da sapere)
La sessione Windows ha riscritto `EFI/BOOT/grub.cfg`, `HANDOFF.md` e `diag.sh` sulla ESP e ha copiato il nuovo kit su Y: **senza prima guardare** che cosa c'era: la sessione live aveva lasciato lì il proprio lavoro. Conseguenze:
- Perso il `grub.cfg` della sessione live (con la voce "FIX TASTIERA" via `devicetree`): ricostruito dalla descrizione (voce 2) e affiancato dalla voce 1.
- Sovrascritti su Y: `HANDOFF.md`, `LEGGIMI.txt`, `1-DIAGNOSTICA.sh`, `2-PROVA-FIX-TASTIERA.sh`, `3-SOSPENSIONE-TEST.sh`, `4-CLAUDE-CODE.sh`. Il HANDOFF della sessione live è stato recuperato dai settori grezzi (file `…recuperato.md`); eventuali modifiche fatte dalla sessione live agli altri cinque file non sono recuperabili.
- Tutti gli altri file della sessione live (script 5, 6, 7, `fix-tastiera/`, `audio/`, `upstream/`, esiti) sono intatti.
Regola: prima di scrivere sulla chiavetta, elencare ESP e STRUMENTI e confrontare con quanto ci si aspetta.

## 7. Fatti verificati su Windows
- DTB Fedora 7.2.11: senza nodo EC e senza riserva del GPIO 65 (reset EC, da non toccare; commit kernel af7ef48feed1 e a92ac66d35df). Aggiornamenti Fedora 45: kernel 7.3.3.
- Firmware richiesti dal DTB: `qcom/x1e80100/LENOVO/83ED/{qcadsp8380.mbn,adsp_dtbs.elf,qccdsp8380.mbn,cdsp_dtbs.elf,qcdxkmsuc8380.mbn,qcvss8380.mbn}`; in `firmware/` le versioni prese dal DriverStore di Windows + topologia + firmware GPU, con SHA256SUMS.
- Secure Boot: shim Fedora 45 firmato **Microsoft UEFI CA 2023**; Windows ha `C:\Windows\System32\SecureBootUpdates\DBUpdate3P2023.bin`; procedura in `secureboot/LEGGIMI.txt` (non provata). sbctl non è nei repo Fedora 45.
- La live applica da sola il contenuto di `/updates` di un initrd aggiuntivo (`20-apply-live-updates.sh`).
- WSL Ubuntu 26.04 arm64 su Windows (python3, 7z) serve per estrarre DTB/initrd e collaudare. Collaudo del kit: 26 controlli superati (sintassi, cpio, simulazione hook, patcher, script 1, 8, 12 su radici finte). **Nessuno script nuovo è stato eseguito sul portatile sotto Linux.**

## 8. Da evitare
- Ventoy (non firmato su ARM64; modalità GRUB2 → `invalid magic number`); adattatore ASMedia; `Clear-Disk` (usare `diskpart clean`).
- PowerShell elevato: script `.ps1` con `-File`; `[uint32]3221225472` al posto di `0xC0000000`; niente `[math]::Min` con long.
- WSL: lanciare da PowerShell con script su file; ogni chiamata riparte da zero.
- Caricare moduli che alzano il guadagno degli altoparlanti o inviare mail upstream senza decisione esplicita dell'utente.

## 9. Prossimi passi
1. Avvio a freddo della chiavetta lasciando partire la voce 1: tastiera e touchpad devono andare subito e l'audio deve uscire dall'uscita "Altoparlanti potenziati". Poi leggere `STRUMENTI/log/` (autorun.log, riepilogo). Se la tastiera non va: voce 3 o 4 + `5-FIX-TASTIERA-SUBITO.sh`.
2. Installare Fedora in dual boot dalla stessa sessione (non toccare le partizioni Windows; spazio da ricavare da D: o C:). A fine installazione `dopo-anaconda.sh` gira da solo: controllare `/var/log/yoga-slim7x-installazione.log` nel sistema installato o `STRUMENTI/log/dopo-anaconda-*.txt`. Se non fosse partito: `sudo bash 12-TASTIERA-FIX-PERMANENTE.sh --dalla-live` prima di riavviare, poi `10-DOPO-INSTALLAZIONE-FEDORA.sh`.
3. Dopo `sudo dnf upgrade --refresh` con kernel nuovo: l'aggancio corregge da solo il kernel; `wsagain` va ricompilato (lo fa `audio-ampli.sh` se ci sono kernel-devel, gcc, make).
4. Audio "come Windows": non raggiungibile (Dolby Atmos). Taratura Dolby del modello in `audio-auto/windows-dolby-taratura.txt` per un'eventuale equalizzazione a orecchio.
5. Upstream: inviare segnalazione e patch solo dopo conferma a freddo e approvazione dell'utente.
6. Secure Boot: decidere tra le scelte a/b/c di `secureboot/LEGGIMI.txt`.

Fonti: https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install · https://fedoraproject.org/wiki/Yoga_Slim7x · https://support.microsoft.com/help/5068202

## 10. Copia su GitHub
- Repository **privato**: https://github.com/mich-de/yoga-slim7x-linux (copia locale `D:\linux\repo`, ramo `main`). Contiene tutto il kit, compresi file proprietari presi da Windows e log: non renderlo pubblico.
- Struttura: `strumenti/` (copia di Y:), `chiavetta-efi/` (menu GRUB, `strumenti.cpio` e suo sorgente), `sorgenti/` (script Windows, prove in macchina virtuale, analisi), note di progetto nella radice.
- Per aggiornare: ricopiare i file cambiati in `D:\linux\repo`, poi `git add -A && git commit && git push`. Le credenziali di git passano da GitHub CLI (`gh auth setup-git` già eseguito; se scadono: `gh auth login --web`).
- La ISO di Fedora e l'immagine di prova `D:\linux\_vm\stick.img` non sono nel repository.

## 11. Aggiornamento 16/11 notte: primo avvio reale e seconda passata di reverse
### Primo avvio reale della chiavetta (prima voce "TUTTO AUTOMATICO"), due avvii, log in `STRUMENTI/log/`
- Desktop Plasma partito in entrambi, nessuna unit fallita.
- Tastiera: bus a 100 kHz, nessun errore I2C, driver `i2c_hid_of` e HID `lenovo`, dispositivo di input `event1` creato. Che i tasti scrivano lo deve confermare l'utente (interrupt della tastiera contati: 3 e 1).
- Touchpad e touchscreen: `hid-multitouch`, multitocco presente, quindi gesture disponibili.
- Audio: scheda rilevata, uscita `effect_input.yoga_spk` predefinita, `wsagain` caricato, PA Volume 18/18/16/16. Che si senta lo deve confermare l'utente.
- Righe rosse all'avvio, tutte innocue: `cdsp_dtbs.elf -2` (il CDSP non serve), `pmic_glink Failed to create device link` (noto), `gen70500_sqe.fw` assente nell'initrd (caricato dopo, a 54 s: `Loaded GMU firmware v4.3.17`), `qcom-apm CMD timeout [1001021]` (DSP non ancora pronto, la scheda nasce subito dopo).
- KO attesi nella live: CDSP, webcam, cpufreq (lo sistema `dopo-anaconda.sh`), TPM.
- Corretti 3 falsi KO della diagnostica (`lib/comune.sh` `kbd_event`, `1-DIAGNOSTICA.sh` controlli GPU e uscita audio), provati sui dati veri.
- Fedora NON ancora installata. Disco interno invariato (C: 554,6 GB, D: 396,9 GB, nessuno spazio libero). Domanda aperta: ridurre D: di 100 GB.

### Seconda passata di reverse dell'audio di Windows
Dettagli in `audio-auto/REVERSE-AUDIO-WINDOWS.md` punto 5. In breve: la prima passata aveva guardato il sottografo sbagliato; la catena vera usa il modulo Lenovo `0x0701000B` con una taratura da 54 KB (incrocio a 2400 Hz, due curve di equalizzazione, passa-alto); identificati SOFT_PAUSE e l'instradatore CPS; `qwsp` cifrato; trovati progetti pubblici gemelli (Dell XPS 13 9345 e Surface Pro 11).

### Prossimi passi (prevalgono sul punto 9 dove in conflitto)
1. Utente: dire se tasti e suono funzionavano; decidere la riduzione di D:; installare Fedora dalla prima voce.
2. Sotto Linux: provare il compander WSA884x spento (UCM) con misura al microfono; capire i canali delle curve Lenovo e portarle in PipeWire senza alzare i guadagni.
3. Commit nuovi solo locali in `D:\linux\repo`: il push richiede la conferma dell'utente.
