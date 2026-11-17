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

## 12. Esito dell'utente e webcam (16/11 notte)
Confermato dall'utente sul portatile, con la prima voce del menu: **tastiera e touch (gesture) funzionano**. Audio "non come in Windows". Webcam non funziona.

### Webcam: causa (visto)
- Sensore: OV02C10 (INF di Windows `qccamfrontsensor*`, e alberi del kernel non ufficiali).
- Kernel Fedora 7.2.11: i driver ci sono (`qcom-camss` con `qcom,x1e80100-camss`, `ov02c10`, `i2c-qcom-cci`, `CONFIG_CLK_X1E80100_CAMCC=m`); libcamera 0.7.2 presente nella live.
- Manca il device tree: nel DTB del Yoga non esistono `camcc`, `cci`, `camss` né il sensore; nessun DTB `x1e*`/`x1p*` del kernel 7.2.11 ha un sensore `ovti,ov02*`; nel kernel ufficiale (ricerca su GitHub, ramo principale) nessun dts contiene `ovti,ov02`.
- Descrizione funzionante fuori dal kernel ufficiale: `aruhier/linux-slim7x-x1e` (ramo `custom/7.3.3`, aggiornato il 09/11/2026) e `endlessm/linux`. Cablaggio dal loro dts: sensore su `cci1` bus 1, indirizzo 0x36, reset `tlmm 237`, clock `CAM_CC_MCLK4_CLK` a 19,2 MHz, alimentazioni `vreg_l7b_2p8`, `vreg_l1m_1p2`, `vreg_l3m_1p8`, `csiphy4`, 2 corsie dati, 400 MHz, pin con funzione `cam_aon`.
- Quell'albero usa nodi `csiphy4` separati (driver camss modificato). **Dedotto**: i suoi nodi non vanno bene così come sono per il driver del kernel 7.2.11; va seguito il binding `qcom,x1e80100-camss.yaml` del kernel in uso.

### Strade per la webcam
1. Aggiungere al DTB (stesso meccanismo della correzione tastiera) `camcc`, `cci1`, `camss` secondo il binding del kernel in uso, più il sensore con il cablaggio qui sopra. È sviluppo, con prove sul portatile sotto Linux. Rischio: tensioni dei regolatori sbagliate possono danneggiare il sensore, quindi copiare i valori esatti dall'albero funzionante. Il DTB cresce: la sostituzione in posto usata per la tastiera non basta, va rifatta la sezione `.dtbauto` del kernel o usato un DTB esterno.
2. Usare il kernel `aruhier/linux-slim7x-x1e` (da compilare; Secure Boot da rivedere).
3. Aspettare il kernel ufficiale.

### Audio
Vedi punto 11 e `audio-auto/REVERSE-AUDIO-WINDOWS.md` punto 5. Catena PipeWire attuale (`audio/50-yoga-altoparlanti.conf`): incrocio woofer/tweeter a 3000 Hz, passa-alto a 110 Hz. Taratura Lenovo: incrocio a 2400 Hz e due curve di equalizzazione.

### Ordine consigliato
Installare Fedora (serve spazio: ridurre D:, in attesa di conferma), poi lavorare su audio e webcam da Fedora installata con Claude (`bash 4-CLAUDE-CODE.sh`), dove si può misurare con il microfono e riavviare per provare.

## 13. Dischi di Windows da Fedora (16/11 notte)
- Problema riferito dall'utente: D: non si apre da Fedora.
- Causa (**visto**): `nvme0n1p3` (C:) e `nvme0n1p4` (D:) sono volumi BitLocker (`lsblk` nella diagnostica). In Windows lo stato è 7, "in attesa di attivazione": cifrati, con la chiave in chiaro sul disco e nessuna password.
- Rimedio nella live: `avvio/autorun-root.sh` apre da solo i volumi BitLocker con `cryptsetup open --type bitlk` (la chiave in chiaro non richiede password: **visto** nel sorgente `lib/bitlk/bitlk.c` di cryptsetup). Compaiono come `/dev/mapper/win-nvme0n1p3` e `win-nvme0n1p4`, apribili da Dolphin. Esito scritto in `log/autorun.log`. **Non provato sul portatile.**
- Non fatto: la stessa cosa per Fedora installata (serve una voce in `/etc/crypttab`, da aggiungere in `dopo-anaconda.sh`).
- Alternativa definitiva da Windows, solo con la conferma dell'utente: decifrare D: (`manage-bde -off D:`). Con la chiave in chiaro la cifratura attuale non protegge comunque i dati.
- Avvio rapido di Windows: `HiberbootEnabled=1` ma `hiberfil.sys` non esiste, quindi non blocca i volumi.
- **Aggiornamento 16/11 ore 23:18**: su richiesta esplicita, D: decifrato da Windows (`manage-bde -off D:`). Verificato: "Decrittografia completata", 0%, nessuna versione BitLocker; ora è NTFS in chiaro e Fedora lo apre direttamente. C: invariato (BitLocker con chiave in chiaro, lo apre `autorun-root.sh`). Se in futuro Windows attiva la cifratura del dispositivo (accesso con account Microsoft), D: può essere cifrato di nuovo.

## 14. CentroAI anche per Linux (16/11 notte)
- `D:\CentroAI\Installa-CentroAI-Linux.sh`: installer per Fedora e Ubuntu (aarch64 e x86_64). Da Linux: `bash <cartella CentroAI>/Installa-CentroAI-Linux.sh`. Programmi in `app-linux/`, comandi in `bin-linux/` e in `~/.local/bin`, configurazione di Claude in `data/claude-linux/` (regole, skill e hook presi da quella di Windows; login e plugin separati).
- Provato in WSL Ubuntu 26.04 ARM64: Claude Code 2.1.326, Node v26.13.1, gh 2.104.0, opencode 2.3.0, plugin ponytail e superpowers. Non provato su Fedora né su NTFS montato da Linux.
- Sostituisce `4-CLAUDE-CODE.sh` quando D: è montato: i programmi sono già scaricati, serve la rete solo per il login.
- Hook resi compatibili con Linux: `image_read_as_text.py` (tesseract), `pdf_read_as_text.py` (pdftotext facoltativo).

## 15. Sessione dalla live Fedora, 16/11 ore 23 (Claude avviato da CentroAI su D:, non dallo script 4)
Prevale sui punti 4, 11 e 12 dove in conflitto. Dettagli e numeri: `audio-auto/REVERSE-AUDIO-WINDOWS.md` punto 6.

### Audio: fatto e misurato
- Nuovi strumenti nel kit: `tools/misura-audio.py` (toni, sweep, catena simulata; serve `python3-numpy`) e `tools/ctl-amplificatori.sh`.
- **Causa del volume basso trovata** (dopo il primo giudizio dell'utente: "sempre bassissimo"): il kernel tiene apposta gli amplificatori al guadagno minimo perché manca la protezione degli altoparlanti. `PA Volume` vale 21 − 1,5×(31 − v) dB (17 = 0 dB, 31 = 21 dB), è letto solo quando l'uscita riparte dopo la sospensione, ha un tetto nel driver della scheda (6; `wsagain cap=N` lo alza) e l'UCM lo riporta a 12 a ogni attivazione. Guadagno pieno misurato: +24 dB rispetto a ora. La frase "PA Volume è inerte" scritta prima era sbagliata (prova fatta senza lasciar sospendere l'uscita). Dettagli: REVERSE punto 6a. **Alzare il guadagno è una decisione dell'utente** (chiesta in questa sessione); per renderla stabile vanno cambiati il valore nell'UCM (`codecs/wsa884x/four-speakers/SpeakerSeq.conf`) e `cap` in `avvio/audio-ampli.sh`.
- Modulo di prova `audio/wsareg/` (scrive un campo di registro degli amplificatori): solo per misure.
- Compander: spento o acceso non cambia nulla (già spento lato codec nel profilo UCM). Strada chiusa.
- Causa del suono cupo trovata: con la catena vecchia buco di 11–14 dB a 2 kHz e acuti 6–8 dB sotto i medi (incrocio a 3 kHz troppo alto per questi woofer, tweeter invertiti e troppo bassi).
- **Nuova `audio/50-yoga-altoparlanti.conf`** (attiva in questa live in `/etc/pipewire/filter-chain.conf.d/`, copiata nel kit e nel repo): passa-alto 180 Hz 4° ordine, incrocio 2400 Hz, tweeter −7 dB non invertiti, −4 dB a 560 Hz sui woofer, +3 dB a 6,5 kHz sui tweeter. Misurato sulla catena vera: scarto 400–8000 Hz da 3,4 a 1,8 dB. **Giudizio a orecchio dell'utente: da avere.**
- Taratura Lenovo: struttura decodificata (8 unità FIR + 12 biquad); assegnazione ai canali solo dedotta; non copiata perché manca il rapporto di guadagno woofer/tweeter di Windows.
- Da fare se serve ancora: volume massimo (il margine vero è `WSA WSA_RX* Digital Volume`, ora 81 su 124, cioè −3 dB: **non toccato**, senza protezione è un rischio e serve la decisione dell'utente); virtualizzatore per la spazialità.

### Webcam: solo verifiche di fattibilità (nessun file scritto)
- Kernel live: `CONFIG_OF_OVERLAY=y`, `OF_DYNAMIC=y`, device tree vivo con `__symbols__` (707 etichette). Non esiste l'interfaccia configfs per gli overlay: per provare a caldo serve un piccolo modulo che chiama `of_overlay_fdt_apply()` (stessa tecnica di `i2cslow2`). Così i nodi si provano senza riavviare.
- Etichette presenti: `tlmm`, `gcc`, `rpmhcc`, `rpmhpd`, `intc`, `pm8010`, `camera_mem`. **Assenti**: `camcc`, `cci*`, `camss`, e anche i regolatori `vreg_l7b_2p8`, `vreg_l1m_1p2`, `vreg_l3m_1p8` (vanno aggiunti i regolatori RPMh del PM8010 e L7B, con le tensioni esatte dell'albero `aruhier/linux-slim7x-x1e`).
- Driver nel kernel: `qcom-camss`, `ov02c10`, `i2c-qcom-cci`, `camcc-x1e80100` (moduli). libcamera 0.7.2 presente; nessun `/dev/video*`.
- Prossimo passo: prendere dal kernel 7.2.11 il binding `qcom,x1e80100-camss.yaml` e i nodi `camcc`/`cci`/`camss` di un dtsi che li ha (kernel più recente o albero aruhier), scrivere l'overlay, caricarlo, guardare `dmesg` e `cam -l`.

### Note pratiche della live
- `sudo`: la password di liveuser è vuota ma `sudo -n` fallisce; usare `echo | sudo -S -p '' comando`.
- `amixer cset name=...` non trova i controlli: usare i numid (`tools/ctl-amplificatori.sh`).
- Installati in questa live (si perdono al riavvio): `python3-numpy dtc gcc make kernel-devel-7.2.11-300.fc45 v4l-utils`. L'installazione ha aggiornato anche glibc nell'overlay della live.
- Sorgenti del driver consultati: `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/<file>?h=v7.2.11`.
- Non fatto: commit nel repo (file modificati: `strumenti/audio/50-…conf`, `strumenti/audio-auto/REVERSE-…md`, `strumenti/LEGGIMI.txt`, `strumenti/tools/misura-audio.py`, `strumenti/tools/ctl-amplificatori.sh`, HANDOFF, memory, handover); copia del HANDOFF sulla ESP (non montata).

## 16. Nuovo obiettivo audio deciso dall'utente (16/11 ore 23:50): guadagno pieno con protezione del DSP
Richiesta testuale: "Devi fare reverse per fare protezione del dsp con +24db". Quindi **non** alzare il guadagno senza protezione (proposte +9/+15 dB non accettate): prima va attivata su Linux la protezione altoparlanti dell'ADSP, con i parametri di Windows, poi si porta l'amplificatore a 21 dB.

### Fatti già verificati (non rifare)
- Causa del volume basso e scala di `PA Volume`: punto 15 e REVERSE punto 6a. Guadagno pieno = CSR_GAIN_EN a 0 (modo DRE) oppure `PA Volume` 31; oggi il sistema sta al minimo.
- Kernel 7.2.11, `sound/soc/qcom/qdsp6/audioreach.c`: conosce `MODULE_ID_SPEAKER_PROTECTION` 0x070010E2 e `_VI` 0x070010E3, ma invia solo il modo operativo (`PARAM_ID_SP_OP_MODE` 0x080011E9) e, per VI, modo, mappa canali e modo escursione (0x080011F4, 0x08001203, 0x080011FF). **VI accetta al massimo 2 canali per modulo** (errore oltre): con 4 altoparlanti servono due coppie o una patch. Non invia nessuna taratura.
- `sound/soc/qcom/x1e80100.c` impone i tetti (Digital Volume 81, PA Volume 6) senza condizioni: vanno tolti solo a protezione provata (oggi li scavalca `wsagain cap=N`).
- ACDB del Yoga, parametri dei moduli di protezione (istanze: RX 0x411A, VI 0x4121, instradatore CPS 0x4123):
  - 0x070010E2: 0x080011E8 (68 B), 0x080011EA (4), 0x080011EB (12), 0x080011ED (4), 0x080011EE (2), 0x08001258 (1520), 0x0800125A (2), 0x08001314 (20), 0x0800134A (2188), 0x0800135A (40), 0x08001367 (24), 0x0800150A (20), 0x0800150B (20), 0x0800150C (2), 0x0800150E (1212), 0x08001532 (1692), più 0x08001026 e 0x080010A6.
  - 0x070010E3: 0x080011C2 (4), 0x080011F6 (44), 0x08001203 (36), 0x08001364 (12), 0x08001384 (2084), 0x08001510 (20), 0x08001535 (212).
  - Estrazione: `tools/re-audio/acdb_scan.py` produce il json con (istanza, modulo, parametro, offset nel POOL, dimensione).
- Topologia in uso: `/lib/firmware/qcom/x1e80100/LENOVO/83ED/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin.xz` (932 byte, senza protezione). `alsatplg` non è installato nella live; `m4` sì.
- Driver Windows: nessuna tabella di registri WSA884x nei `.sys`; `AcdbGetWsaCfg` legge dalla sezione dati-driver dell'ACDB (GCLU/GCKT/GCDT/GCDE/GCDO; moduli 0x8000020–0x8000090, decodificati solo come byte). Il modulo 0x800002A/0x800002B è la tabella dei passi di volume in Q28.
- C: è montato in sola lettura in `/mnt/win` in questa live (DriverStore consultabile).

### Piano per la prossima sessione
1. Leggere il progetto gemello `geocausa/SP11X1e-audio` (Surface Pro 11, stessa protezione v5): topologia, patch al kernel, come manda le tarature. È il modello da adattare a 4 altoparlanti.
2. Decodificare i parametri dell'ACDB qui sopra con le intestazioni pubbliche `AudioReach/audioreach-graphservices` (`spf/api/modules/`: protezione RX, VI, CPS): resistenza, limiti termici, escursione, mappa canali.
3. Costruire la topologia del Yoga con protezione RX + ritorno V/I (sorgenti `audioreach-topology`, serve `alsatplg` da `alsa-utils`) e i moduli `snd-q6apm`/audioreach del 7.2.11 ricompilati fuori albero con l'invio delle tarature (`kernel-devel` va reinstallato a ogni avvio della live).
4. Prove nell'ordine: modo calibrazione (lettura di resistenza e temperatura) → modo normale a guadagno basso → verifica che la protezione intervenga davvero → solo allora guadagno pieno, a passi, con `tools/misura-audio.py`.
5. Vincolo: nella live tutto si perde al riavvio; il lavoro lungo conviene farlo su Fedora installata (riduzione di D: ancora da confermare).
Modello: è reverse più sviluppo kernel; sceglierlo a inizio chat (regole: Opus 4.6 per il reverse, Opus 5.5 per lo sviluppo).

## 17. Protezione altoparlanti: reverse chiuso, dati pronti (16/11 notte, sessione "protezione audio")
Prevale sul piano del punto 16 (passi 1 e 2 fatti). Dettagli: `audio-auto/REVERSE-AUDIO-WINDOWS.md` punto 7. **Niente caricato nel kernel, nessun guadagno toccato.**

### Fatto
- Letto il progetto gemello `geocausa/SP11X1e-audio` (kernel 7.1.5 dedicato, ~80 patch; licenza BSD-2 per i suoi strumenti). I suoi strumenti ACDB funzionano sull'ACDB del Yoga.
- Grafo di Windows del Yoga (`0xB0000001`): SP_RX `0x411A`, SP_VI `0x4121` alimentato da CODEC_DMA_SOURCE `0x411B`, CPS `0x4123`; control link SP_VI↔SP_RX (intento `0x08001204`) e CPS↔SP_RX (`0x08001537`). Strumento: `tools/re-audio/acdb_graph.py`.
- Tarature a 4 altoparlanti estratte (tag `0x0401000A`, `0x0401000B`, endpoint V/I `0x04010005`: 8000 Hz, 32 bit, 4 canali, LPAIF WSA indice 1, maschera `0xF`) più la taratura di sottografo.
- R0/T0 di questo portatile dal registro di Windows (`tools/re-audio/hive_spkr.py`): 3,883 / 3,640 / 4,252 / 4,007 Ω a 42–44 °C.
- **File per il DSP**: `audio/protezione/yoga-slim7x-spkr-prot.bin` (42 frame, 15624 byte), generatore `tools/re-audio/acdb_prot_blob.py`. Nel kit e sulla chiavetta.
- Intestazioni pubbliche con le strutture: `AudioReach/audioreach-graphservices`, `spf/api/modules/sp_vi.h`, `sp_rx.h` (versione 7: identificativi diversi dalla v5 del Yoga, campi simili), `cps_data_router.h`.

### Che cosa va costruito (ordine consigliato; è sviluppo kernel: modello Opus 5.5)
1. **Topologia** (`dnf install alsa-topology-utils` per `alsatplg`): partire da `linux-msm/audioreach-topology`, `X1E80100-LENOVO-Yoga-Slim7x.m4`; nel sottografo del dispositivo WSA mettere SP_RX fra LOG e l'endpoint e un secondo contenitore CODEC_DMA_SOURCE → SP_VI, con gli IID di Windows (`0x411A`, `0x4121`, `0x411B`). Mancano le macro m4 per i due moduli: vanno scritte (modello: `audioreach/module_log.m4`).
2. **`snd-q6apm` fuori albero** dai sorgenti 7.2.11 (`sound/soc/qcom/qdsp6/{q6apm,audioreach,topology}.c`; `kernel-devel` va reinstallato a ogni avvio della live): (a) control link SP_VI↔SP_RX nel GRAPH_OPEN (parametro `0x08001061`; modello: patch 0003 del progetto gemello); (b) dopo il modo SP_RX, invio dei frame del file con `request_firmware`, uno per comando, senza fermarsi su un frame rifiutato ma scrivendolo in `dmesg`; (c) per SP_VI saltare la configurazione del driver (limite a 2 canali) quando c'è il file; (d) formato della sorgente V/I fisso a 8000 Hz / 32 bit / 4 canali; (e) lettura della telemetria (`0x080011F2`) in `dmesg` o debugfs.
3. **Ritorno V/I dall'hardware**: `VISENSE Switch` dei 4 amplificatori, `WSA_SPKR_VI_1/2` delle due macro, e il DAI `WSA_AIF_VI` (indice 2) attivo. Nel device tree manca il collegamento `WSA_CODEC_DMA_TX_0`: o overlay a caldo (tecnica di `i2cslow2`) più riaggancio della scheda, o DTB corretto all'avvio, o macro WSA fuori albero che accende il ritorno insieme alla riproduzione. **Da decidere con una prova**: è il punto più incerto (nel progetto gemello ha richiesto molte iterazioni: V e I alternati con `TOP_CFG1=0x03`, porte PBR/CPS condivise fuori dallo stream).
4. **Prove, in quest'ordine, sempre a guadagno attuale**: il grafo si apre con i moduli → tutti i frame accettati → la telemetria dà resistenze vicine a R0 (3,6–4,3 Ω) e temperature plausibili → solo allora, con la conferma dell'utente, si alza il guadagno a passi misurando con `tools/misura-audio.py`. Se la telemetria non è credibile, il guadagno non si tocca.
5. CPS (`0x4123`) lasciato fuori dal primo giro.

### Note
- Lavoro lungo: conviene Fedora installata (nella live si perde tutto al riavvio). Riduzione di D: ancora da confermare.
- Sorgenti scaricati in questa sessione (si perdono al riavvio): scratchpad `src/` (tre repository) e `k/` (file del kernel 7.2.11 da git.kernel.org).
- Non fatto: commit e push del repo (serve la conferma), copia del HANDOFF sulla ESP (non montata).

## 18. Protezione altoparlanti: lato DSP funzionante, manca il ritorno V/I (17/11 notte, sessione "protezione audio, punto 17")
Prevale sul punto 17 dove in conflitto. File: `repo/strumenti/audio/protezione/` (indice: `LEGGIMI.txt` lì dentro), copiati anche sulla chiavetta. **Nessun guadagno alzato.**

### ATTENZIONE: stato in cui è rimasta la live
**L'audio è fermo fino al riavvio.** Causa: errore mio nel percorso `scambia.sh off` (porta GPR registrata di nuovo mentre il puntatore di callback indicava ancora il modulo scaricato → Oops del kernel a 5374 s nel thread che riceve i messaggi del DSP). Corretto in `kernel/gprport.c` (azzera la callback se non c'è un driver agganciato), ricompilato, **non riprovato** (serve un riavvio). Al riavvio la live torna da sola allo stato di serie (driver, topologia, volume di `audio-ampli.sh`); nulla di questa sessione è permanente. Si perdono: pacchetti installati (`kernel-devel gcc make patch alsa-topology-utils python3-numpy`), scratchpad.

### Fatto e provato sul portatile
1. **Topologia** con SP_RX `0x411A`, sorgente V/I `0x411B`, SP_VI `0x4121` (`topologia/build.sh`). La topologia di serie ricompilata dagli stessi sorgenti è identica byte per byte a quella installata. Il kernel la chiede come `qcom/x1e80100/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin` (non in `LENOVO/83ED/`): va in `/lib/firmware/updates/qcom/x1e80100/`.
2. **`snd-q6apm` modificato** (`kernel/q6apm-sp.patch`, 446 righe di diff sui sorgenti 7.2.11): control link SP_VI↔SP_RX generato dal driver quando il grafo contiene i due moduli; tarature da file firmware (parametro `sp_cal`), un `SET_CFG` per frame in banda; sorgente V/I e SP_VI configurate solo dal file; lettura parametri con `getcfg`. Costruito accanto a quello di serie (moduli `snd-q6apm-sp`, `q6apm-dai-sp`, `q6apm-lpass-dais-sp`, simboli con prefisso `sp_`) perché `snd_q6apm` di serie non si può scaricare (lo usa `q6prm`, da cui dipendono clock e SoundWire).
3. **Esito sul DSP**: grafo aperto senza errori, **45 frame inviati, 0 rifiutati**; rilettura: SP_RX in modo normale, statico a 48 kHz/4 altoparlanti, versione 5.1.2.0 (`0x080011F3`); SP_VI con 4 altoparlanti, 8000 Hz, temperatura massima 100 °C.
4. **Misura ai microfoni** (PA Volume 6, toni −40/−30/−20 dBFS): con protezione woofer −22,0/−21,5/−22,0, tweeter −23,0/−22,8/−22,8; con topologia di serie −21,7/−21,8/−22,0 e −22,1/−22,1/−22,2. Quindi senza ritorno V/I SP_RX lascia passare il suono quasi invariato (≤0,9 dB): **non protegge e non limita**.
5. **Modo calibrazione** (file `…-calibrazione.bin`, stato letto con `0x4121 0x080011F8`): senza nulla = stato 1 (porta V/I ferma); con il percorso V/I delle due macro acceso (`kernel/wsavi.ko en=1`: `TXn_SPKR_PROT_PATH_CTL` = 0x10, `TOP_CFG1` = 0x03) = stato 2 poi **7 (attesa V/I scaduta)**. Quindi DSP, DMA e macro funzionano; non arrivano i segnali dagli amplificatori.

### Che cosa manca (prossima sessione; sviluppo kernel)
- **Trasporto SoundWire dei segnali V/I** dai 4 WSA884x (porta 5 di ogni amplificatore, porte master 10 e 11 dei controller `swr0` e `swr3`). `VISENSE Switch` da solo non basta: mette la porta nello stream di riproduzione (direzione RX) e `qcom_swrm_stream_alloc_ports` la rifiuta perché 10/11 sono oltre le porte di uscita (dedotto dal sorgente, **non provato**). Nel progetto gemello: secondo DAI sul WSA884x con direzione TX, collegamento nel device tree con il DAI di cattura del controller e `lpass_wsamacro 2`, correzioni ai parametri di trasporto delle porte (patch 0020, 0050, 0065, 0067, 0070 di `geocausa/SP11X1e-audio`). Da leggere: `drivers/soundwire/qcom.c` v7.2.11 e i `qcom,ports-*` di `swr0`/`swr3` nel dtsi.
- Poi: calibrazione riuscita (stato 4, R0 fra 3,6 e 4,3 Ω) → modo normale → prova che la protezione interviene → solo allora guadagno, a passi, con conferma dell'utente.
- Lettura dal vivo di resistenza/temperatura in modo normale: non trovata (`0x080011F2` su SP_RX dà errore 1, come nel progetto gemello). In calibrazione c'è `0x080011F8`.
- Fuori dal primo giro: CPS (`0x4123`); invio fuori banda (non serve: i frame in banda passano tutti).

### Scoperte sul kernel 7.2.11 (da sapere)
- `drivers/soc/qcom/apr.c`: lo sgancio di un driver toglie la porta del servizio dal router e nessuno la rimette (un secondo aggancio non riceve più risposte: "GPR: Port(1) is not registered"); e non azzera `svc.callback`. Per questo esiste `gprport.ko`. Con i moduli caricati all'avvio (sistema installato) il problema non c'è.
- `q6apm.c`: la risposta a `SHARED_MEM_UNMAP_REGIONS` non sveglia mai chi aspetta (confronta l'opcode sbagliato): 5 s persi per mappatura a ogni rimozione della scheda. Innocuo.
- Comandi scaduti lasciano al DSP mappature orfane (poi `MAP_REGIONS` dà errore 1): si puliscono con `APM_CMD_CLOSE_ALL` (0x01001013).
- `scambia.sh on` e `ricarica` hanno funzionato; `off` no (vedi sopra). Durante lo scambio il portatile non deve sospendersi.

### Per ripartire dalla live dopo il riavvio
`sudo dnf -y install kernel-devel-$(uname -r) gcc make patch alsa-topology-utils python3-numpy` (solo per ricompilare; i `.ko` per 7.2.11-300.fc45 sono già in `kernel/7.2.11-300.fc45.aarch64/`), poi `sudo bash repo/strumenti/audio/protezione/kernel/scambia.sh on`, suonare qualcosa, leggere `dmesg | grep 'speaker protection'`. Sorgenti di riferimento da riscaricare se servono: `geocausa/SP11X1e-audio`, `linux-msm/audioreach-topology`, `AudioReach/audioreach-graphservices`.

### Non fatto
Commit e push del repo (serve la conferma), copia del HANDOFF sulla ESP (non montata), modello: sessione su Fable 5.2 (regola: Opus 5.5 per lo sviluppo).

## 19. Ritorno V/I: flusso SoundWire pronto, prova con il DSP da fare dopo il riavvio (17/11 ore 00:40)
Prevale sul punto 18 dove in conflitto. **Nessun guadagno alzato. La live NON e' stata riavviata: l'audio e' ancora fermo (Oops del punto 18); serve un riavvio prima di qualsiasi prova con il suono.**

### Fatto
- `kernel/wsavi.c` riscritto: finche' e' caricato apre, per ognuno dei due bus (`sdw-master-1-0` woofer, `sdw-master-4-0` tweeter), uno stream SoundWire con la porta 5 (VISENSE) dei due amplificatori e le porte 10 e 11 del controller (da `qcom,port-mapping`), poi accende il percorso V/I delle macro (come prima). `rmmod` spegne tutto. Parametri: `chmask` (predefinito 3 = V e I, come Windows nel progetto gemello; il driver di serie dichiara 1), `sdw=0` (solo macro). Il parametro `en` non esiste piu'.
- Via scelta: API del bus (`sdw_stream_add_slave/master`, `sdw_prepare_stream`, `sdw_enable_stream`) chiamate dal modulo d'aiuto, senza DAI, senza device tree, senza toccare `wsa884x` ne' `soundwire-qcom`. Lo stream usa direzione RX: per il core e' solo contabilita' (trova la porta 5 in `sink_dpn_prop`), il controller Qualcomm non guarda la direzione. Il modulo tiene svegli amplificatori e bus (riferimenti runtime PM), cosi' lo stream sopravvive a stop e ripartenza della riproduzione.
- **Provato sul portatile (senza DSP, audio fermo)**: trovati i 4 amplificatori su 2 bus, porte 10 e 11, stream preparato e abilitato senza errori; 15 s di tenuta senza collisioni ne' errori di parita' in `dmesg`, amplificatori sempre `Attached`, spegnimento pulito. **Non provato**: che i dati arrivino al DSP (serve l'audio vivo).
- Parametri di trasporto gia' nel device tree (porte 10/11: intervallo 16, offset1 6 e 13, offset2 0xff, bp 1). Fatti dal sorgente 7.2.11: `qcom_swrm_stream_alloc_ports` rifiuterebbe le porte 10/11 in uno stream RX della scheda (per questo `VISENSE Switch` non serve); la via del modulo la scavalca.
- Nuovi: `kernel/prova-vi.sh` (prova completa in modo calibrazione) e `kernel/statovi.py` (decodifica dello stato; verificato sulle 526 risposte di ieri nel journal). `wsavi.ko` per 7.2.11-300.fc45 nel kit e sulla chiavetta.

### Dopo il riavvio (non serve la rete: i `.ko` sono pronti)
1. `sudo bash repo/strumenti/audio/protezione/kernel/prova-vi.sh` (attiva da solo il driver con protezione). Atteso: stato 4 e R0 fra 3,6 e 4,3 ohm.
2. Se resta 7 (attesa V/I scaduta) o 8 (V/I troppo bassi), nell'ordine: (a) `prova-vi.sh 1` (maschera 1); (b) caricare `wsavi.ko` prima di suonare e far ripartire la riproduzione (la calibrazione riparte con V/I gia' presenti); (c) offset2 a 0 sulle porte 10/11 del controller quando attive (patch 0070 del progetto gemello: richiede di scrivere `ctrl->pconfig`, struttura privata di `drivers/soundwire/qcom.c`); (d) registri V/I dell'amplificatore (`WSA884X_VSENSE1`, `ISENSE2`, ADC) confrontati con la sequenza di Windows del progetto gemello (patch 0063).
3. Riuscita la calibrazione: modo normale (`yoga-slim7x-spkr-prot.bin`) con wsavi caricato, prova che la protezione interviene (misura ai microfoni come al punto 18.4), poi integrazione stabile (DAI e device tree, o wsavi caricato dal servizio) e solo allora guadagno, a passi, con conferma dell'utente.
- Per ricompilare servono di nuovo `kernel-devel-$(uname -r) gcc make` (si perdono al riavvio). Sorgenti di riferimento usati: `drivers/soundwire/{qcom,stream}.c` v7.2.11, patch 0020/0050/0065/0067/0069/0070/0072 di `geocausa/SP11X1e-audio`.

### Non fatto
Commit e push del repo (serve la conferma), copia del HANDOFF sulla ESP (non montata). Modello: sessione su Fable 5.2 (regola: Opus 5.5 per lo sviluppo).

## 20. Prova V/I dopo il riavvio; errori dell'avvio controllati e corretti (17/11 mattina)
Prevale sul punto 19 dove in conflitto. **Nessun guadagno alzato** (volume rimesso ai valori dell'avvio: 18/16).

### Prova V/I (punto 19, passo 1): calibrazione fallita, ma i segnali arrivano
- `prova-vi.sh` (maschera 3) dopo il riavvio: scambio `on` riuscito (con il `gprport.ko` corretto), 45 frame su 45; caricato `wsavi.ko`, stato **3 (in corso)** dopo 2 s, poi **5 (fallita)** fisso, **R0 = 2,025 ohm sul solo primo altoparlante**, 0 sugli altri tre. Non piu' 7: il DSP riceve V/I e misura; il risultato e' fuori intervallo (atteso 3,6-4,3) e riguarda un canale solo.
- Ipotesi, nessuna provata: numero e ordine dei canali (`prova-vi.sh 1`), un solo bus dei due arriva al DSP, scala di V o I (registri dell'amplificatore, patch 0063 del progetto gemello), offset2 (patch 0070). Restano valide le alternative (a)-(d) del punto 19.
- Stato lasciato: driver con protezione attivo (tarature normali, `wsavi` scaricato: il suono passa invariato), uscita "Altoparlanti potenziati" e volume come all'avvio. `scambia.sh off` ancora non riprovato: per tornare al driver di serie, riavviare.
- `scambia.sh` non faceva ripartire `filter-chain.service` dopo lo scambio (spariva l'uscita potenziata): aggiunto alla lista dei servizi.

### Errori dell'avvio: corretti
| Errore | Causa | Rimedio |
|---|---|---|
| `FAT-fs (sda3): Volume was not properly unmounted` | STRUMENTI non smontata all'ultimo spegnimento (solo questo avvio; i tre log precedenti sono puliti) | `fsck.vfat -a`: tolto il segno, 303 file, nessun danno. Resta diverso il byte 65 del settore di avvio di riserva (innocuo, fsck non lo tocca) |
| `[KO] CPU frequency scaling` nel riepilogo | Fedora non carica da solo `scmi-cpufreq` (per il sistema installato era gia' in `dopo-anaconda.sh`, per la live no) | `modprobe scmi-cpufreq` in `avvio/autorun-root.sh`: 3 politiche, 710-3417 MHz, `schedutil` |
| `cdsp_dtbs.elf ... -2`, `Failed to load program segments`, `[KO] CDSP` | a linux-firmware di Fedora manca `cdsp_dtbs.elf`; il `qccdsp8380.mbn` della distro e' diverso da quello del kit | `autorun-root.sh` copia la terna del kit (`qccdsp8380.mbn`, `cdsp_dtbs.elf`, `cdspr.jsn`) in `/lib/firmware/updates/` e avvia il remoteproc: `running` |

Blocco nuovo di `autorun-root.sh` provato a mano da zero (CDSP fermato, file tolti, righe eseguite): riuscito.

**CDSP corretto anche alla fonte (initramfs)**: l'errore nasce a 3,6 s, prima di ogni script, perche' nell'initramfs di Fedora c'e' `qccdsp8380.mbn.xz` ma non `cdsp_dtbs.elf`. `strumenti.cpio` ora contiene anche `usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/{qccdsp8380.mbn,cdsp_dtbs.elf}` del kit (la coppia provata a caldo; `updates` ha la precedenza). Percorso `usr/lib/...` e non `lib/...`: nell'initramfs `lib` e' un collegamento e una voce `lib` del cpio lo cancellerebbe. `mk_cpio.py` corretto: convertiva i CRLF anche nei file binari. Nuovo cpio: 3 243 520 byte, parte `/updates` identica alla vecchia, firmware identici al kit (verificato estraendolo). Installato su ESP (`/strumenti.cpio`; il vecchio e' `strumenti.cpio.bak-1711`), `STRUMENTI/boot/`, repo.

**Non ancora provato con un avvio vero** (serve un riavvio). Se al riavvio gli automatismi non partissero (niente audio potenziato, niente `/run/strumenti`): voce 2 del menu, poi rimettere `strumenti.cpio.bak-1711` al posto di `strumenti.cpio` sulla partizione EFI (`/dev/sda2`).

### Errori dell'avvio: di serie, innocui, lasciati
- `dracut-crypt-generator failed with exit status 2`: errore di dracut (`return` fuori da una funzione quando manca `/etc/crypttab`); non c'e' LUKS.
- `MODSIGN: Couldn't get UEFI db list`, `integrity: Couldn't get size`: Secure Boot spento con chiavi vuote.
- `gen70500_sqe.fw` a 4,6 s: manca solo nell'initramfs, caricato a 54 s (GPU a posto). `snd-seq not found`: idem, poi caricato.
- `pmic_glink ... Failed to create device link`, `Handover signaled`, `qcom-apm CMD timeout` (26 s), `ath12k qmi dma allocation failed`: noti.
- `plasma-workspace.target: Found ordering cycle` → `kde-baloo.service` non parte: difetto delle unita' di Plasma (nessun drop-in nostro); l'indicizzatore dei file resta spento.
- `powerdevil ... Permission denied opening /dev/i2c-*` (luminosita' di monitor esterni via DDC), `stratis`, `smartd` sulla chiavetta, `alsactl asound.state`, `qemu-guest-agent`: innocui.
- `[KO] Webcam`, `[KO] TPM`: gia' noti (punti 12 e 15; TPM non supportato). `sudo: a password is required` a 274 s: e' il comando `claude` di CentroAI (`sudo -n true`), non l'avvio.
- Nessuna unita' systemd fallita, nessun Oops, nessun errore -110 sul bus della tastiera.

### File toccati
`repo/strumenti/avvio/autorun-root.sh`, `repo/strumenti/audio/protezione/kernel/scambia.sh`, `repo/strumenti/boot/LEGGIMI.txt`, `repo/strumenti/boot/strumenti.cpio` (tutti copiati sulla chiavetta); `repo/chiavetta-efi/mk_cpio.py`, `repo/chiavetta-efi/initrd/usr/` (nuovo), `repo/chiavetta-efi/strumenti.cpio`; ESP: `strumenti.cpio`, `strumenti.cpio.bak-1711`; filesystem di STRUMENTI (fsck). Nella live, fino al riavvio: `/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/` (CDSP).

### Prossimi passi (per l'audio prevale il punto 21)
1. **Verifica dopo il riavvio** (prima voce del menu): `sudo journalctl -b -p 3 --no-pager | grep -iE 'cdsp|remoteproc|Initramfs|FAT-fs'` deve essere vuoto; `sudo dmesg | grep -E 'remoteproc1|Initramfs unpacking'` deve dare `cdsp is now up` attorno a 3-4 s e nessun `unpacking failed`; `cat /sys/class/remoteproc/remoteproc1/state` = `running`; `ls /sys/devices/system/cpu/cpufreq/` = 3 politiche; ultimo `STRUMENTI/log/riepilogo-*.txt` con `[OK]` su CPU frequency scaling e CDSP; `strumenti.service` riuscito e uscita "Altoparlanti potenziati" presente.
2. V/I: `sudo bash repo/strumenti/audio/protezione/kernel/prova-vi.sh 1`, poi le alternative del punto 19 partendo dal nuovo sintomo (stato 5, un canale, 2,025 ohm).

### Non fatto
Commit e push del repo (serve la conferma), copia del HANDOFF sulla ESP (non montata). Modello: sessione su Fable 5.2 (regola: Opus 5.5 per lo sviluppo).

## 21. Audio come Windows: metodo cambiato, trovate le due cause della calibrazione fallita (17/11 mattina)
Prevale sui punti 19 e 20 per la parte audio. Obiettivo dell'utente (testuale): "clonare via leanrea gli applicativi drivers per far funzionare l'audio a +24db con protezione delle casse, abbiamo gia fatto diverse volte calibrazione senza successo, cambia approccio". **Nessun guadagno alzato.** Dettagli e prove: `audio-auto/REVERSE-AUDIO-WINDOWS.md` punto 9, `audio/protezione/amplificatori/LEGGIMI.txt`.

### Trovato (visto o misurato)
1. **Windows usa 18 dB, non 21**, e un profilo degli amplificatori per carico 4 Ω: record WSA dell'ACDB del Yoga `1, 3, 0, 4, 0, 1` (uguale al Surface Pro 11), selettore di guadagno `0x24`. Il driver `qcaucd8380.sys` del Yoga scrive i registri WSA884x (il punto 6a del reverse diceva di no): sensore di corrente `0x3021 = 0x07` (6 dB), di tensione `0x3020 = 0x67` (−21 dB). Linux lascia `0x27` e `0x87` e altri 26 registri diversi (stadio di potenza compreso).
2. **Causa 1, trasporto**: nel device tree `qcom,ports-offset2` delle porte 10/11 (ritorno V/I) vale `0xff`; il controller legge allora V e I nello stesso bit. Prova: R letto = 15,07/7,01 − 0,13 = 2,02 Ω (costanti della taratura `0x08001535`), uguale ai 2,025 e 2,058 Ω misurati, e insensibile ai guadagni dei sensori. Windows scrive `Offset2 = 0`.
3. **Causa 2, livello**: con `Offset2 = 0` i dati sono veri, ma lo stato va a 7: il pilota (−40 dBFS, atteso 0,110 V di picco, soglia 25 %) con l'amplificatore a 1,5 dB (`PA Volume` 18) arriva a 0,016 V. La taratura presume 18 dB (`PA Volume` 29). L'attesa V/I è di soli 100 ms.

### Fatto
- `kernel/wsavi.c`: parametri nuovi `off2=0` (Offset2 delle porte 10/11, scritto in `ctrl->pconfig` solo se i valori letti coincidono con il device tree del Yoga), `isense=0`, `vsense=3` (sensori come Windows finché il modulo è caricato; wsa884x li rimette a ogni accensione dell'altoparlante). `.ko` per 7.2.11-300.fc45 ricompilato. `prova-vi.sh` passa i parametri in più a `wsavi`; `statovi.py` conosce lo stato 6.
- Nel repo e sulla chiavetta: `audio/protezione/amplificatori/` (profilo di Windows in json, confronto con Linux, note), `tools/re-audio/wsa_profilo.py`, `schermo/profili/` (7 profili ICC di fabbrica del pannello LEN 8AC2 con i rapporti di qualità, copia di `D:\snapcontrol\profiles`).
- Prove di oggi con `prova-vi.sh` (silenzio, `PA Volume` 18/16): A) sensori come Windows, Offset2 `0xff`: stato 3 → 6 → 7, 2,058 Ω sul quarto canale; C) più Offset2 = 0: stato 7 subito, tutto zero.

### RISULTATO (17/11, ore 9:20 circa): calibrazione riuscita
Con il sì dell'utente (prova di 30 s, solo silenzio), `sudo bash kernel/prova-vi-18db.sh 3`: registri a metà prova `0x34b1 = 05` (18 dB), `0x3021 = 07`, `0x3020 = 67` sui quattro amplificatori; **stato 4 (riuscita) dopo 4 s, R0 = 3,840 / 3,594 / 4,218 / 3,983 Ω**. Windows: 3,883 / 3,640 / 4,252 / 4,007 Ω a 42–44 °C: differenza 0,6–1,3 %, stesso ordine dei canali. Il ritorno V/I funziona con le tre condizioni insieme: Offset2 = 0, sensori come Windows, amplificatore a 18 dB. Lo script rimette da solo `PA Volume` 18/16, tetto e volume di PipeWire (verificato). **Il consenso valeva per quella prova: ogni altra prova a 18 dB va richiesta.**

### RISULTATO 2 (17/11, ore 9:50 circa): la protezione termica interviene e usa la temperatura misurata
Con il sì dell'utente (prove a 18 dB, segnali fino a −20 dBFS), `sudo bash kernel/prova-protezione.sh <gradi>`: tre passate di 16 tratti di tono a 1 kHz, −20 dBFS, sui woofer, livello al microfono 0.
| Passata | Obiettivo 30 °C | Obiettivo 45 °C |
|---|---|---|
| tarature normali (90 °C), con V/I | −21 dB costante | −20,2 dB costante |
| obiettivo abbassato, con V/I | −31…−32 dB (attenua circa 11 dB) | parte a −25,5 e in 3 s torna a −19 dB (non attenua) |
| obiettivo abbassato, senza V/I | −32,3 dB (attenua circa 11,5 dB) | −32,0 dB fisso (attenua 12 dB) |
Lettura: il limite vero è `temp_tgt_q6` per altoparlante nel parametro `0x08001532` di SP_RX (90 °C; `0x08001510` di SP_VI non limita nulla); attenuazione massima 12 dB; metodo 2 (stima in avanti: 37,3 °C/W, costanti 1,85 e 7,4 s) con temperatura presunta di 50 °C quando manca la misura. A 45 °C il DSP con V/I vede le bobine più fredde dell'obiettivo (circa 40 °C dalla resistenza) e toglie l'attenuazione; senza V/I resta al massimo. **Quindi con `wsavi` la protezione termica di Windows lavora sulla temperatura misurata.** Senza V/I resta comunque prudente (parte da 50 °C).
Altre misure a 18 dB con protezione attiva: +22 dB rispetto al guadagno minimo di Linux (woofer 1 kHz: uscita al microfono pari all'ingresso; prima −22 dB), distorsione 0,2–1,7 % sui woofer e 1,8–2,6 % sui tweeter, nessun guasto degli amplificatori nel registro del kernel.
Non riuscito: lettura delle statistiche del DSP (`0x080011EF`, `F0`, `F1`, `F2` di SP_RX; `FE`, `150F` di SP_VI): rifiutate dal firmware. Non provato: protezione dall'escursione; livelli sopra −20 dBFS; uso prolungato.

### Prossimi passi
0. Fatti: calibrazione e prova della protezione termica (sopra). Restano, nell'ordine:
   a. **Stadio di potenza come Windows**: riscontro fatto (75 scritture su 79 del profilo sono identiche nel `qcaucd8380.sys` del Yoga; i quattro amplificatori leggono alimentazione "2S" come il Surface, registro `0x3501 = 2`, mentre Linux applica i valori "1S"). Resta da **applicare** il profilo (28 registri diversi: `amplificatori/confronto-linux-2026-11-17.txt`; non toccare le maschere degli interrupt) e verificare che non compaiano guasti.
   b. **Salita a passi oltre −20 dBFS** (−14, −10, −6, 0) a 18 dB con protezione e V/I, misurando compressione e distorsione, sempre con il sì dell'utente.
   c. **Uso quotidiano**: servizio che carica `wsavi` quando l'uscita parte e lo toglie quando si ferma (i sensori vengono riscritti da wsa884x a ogni accensione; Windows accende prima gli amplificatori e poi i clock di protezione), driver con protezione attivo dall'avvio, `PA Volume` 29, catena PipeWire da ritarare per il nuovo guadagno (oggi compensa un amplificatore 16–19 dB più basso).
   d. `qcom,ports-offset2 = 0` per le porte 10/11 nel device tree interno al kernel, così il trasporto è giusto senza toccare strutture private.
1. **Calibrazione con l'amplificatore a 18 dB e solo silenzio** (serve il sì dell'utente: è un aumento di guadagno, anche se il solo segnale è il pilota a −40 dBFS, circa 1,5 mW): volume di PipeWire basso, `wsagain cap=29`, `PA Volume` 29 sui quattro, uscita fatta ripartire, `sudo bash prova-vi.sh 3`, poi `PA Volume` di nuovo 18/16. Atteso: stato 4 e R0 vicini a 3,88 / 3,64 / 4,25 / 4,01 Ω meno qualche percento (ora gli altoparlanti sono più freddi dei 42–44 °C di Windows).
2. Riuscita la calibrazione: modo normale con `wsavi` caricato; prova che la protezione interviene; riscontro nel driver del Yoga dei registri dello stadio di potenza (OCP `0xf6`, soglie, limiti) e loro applicazione; solo allora 18 dB d'uso, a passi.
3. Integrazione stabile: `qcom,ports-offset2 = 0` per le porte 10/11 nel device tree interno al kernel (4 byte, come la correzione della tastiera), profilo dei sensori dentro `wsa884x` (fuori albero) o nel servizio, `wsavi` caricato dal servizio dopo l'accensione degli amplificatori.
4. Verifica dell'avvio a freddo: punto 20.

### Stato lasciato
Driver con protezione attivo (tarature normali, `wsavi` scaricato, sensori e Offset2 ai valori di Linux), uscita potenziata e `PA Volume` 18/16 come all'avvio. C: montato in sola lettura in `/mnt/win`. Nella live (si perdono al riavvio): `kernel-devel gcc make`, scratchpad con i sorgenti (`k/` kernel 7.2.11, `src/SP11X1e-audio`, `src/hdr/sp_vi.h`, disassemblato `re/qcaucd/dis.txt`).

### In pausa (17/11, ore 10:15): l'utente ha chiesto di ricreare l'app Dolby per Fedora (punto 22)
Stato sicuro: `PA Volume` 18/16, nessun modulo di prova caricato, driver con protezione attivo. Visto in più nel `qcaucd8380.sys` del Yoga: `UVLO_PROG` e `BOP2_PROG` sono calcolati come `n | n << 4` con tre casi (`0x33`/`0x44` per l'alimentazione 2S, `0x99`/`0x66` = i valori che Linux ha oggi); `CURRENT_LIMIT` passa da `0xd4` a `0x44` in un ramo. La tabella delle soglie CLSH non compare come costanti (calcolata). Progetto pronto per riprendere: modulo `wsaprof` che scrive ad amplificatori fermi i registri che Linux non riscrive mai (alimentazione 2S, OCP, soglie, DAC_VCM), `wsavi` che aggiunge a ogni riproduzione `CURRENT_LIMIT 0x44`, `PWRSTG_DBG 0x0c`, `PDRV_HS_CTL 0x5a`, servizio che carica `wsavi` quando l'uscita parte, `PA Volume` 29 woofer / 27 tweeter per mantenere il bilanciamento della catena attuale, salita a passi oltre −20 dBFS con il sì dell'utente.

## 22. App audio per Fedora con gli algoritmi Dolby del portatile (17/11, ore 10:30): studio in corso
Obiettivo dell'utente (testuale): "ricreare l'app dolby anche per fedora"; poi: "devo usare questi algoritmi proprietari, lancia 10 agenti opus 4.6 per studiare". Il lavoro sugli amplificatori (punto 21) è in pausa.

### Deciso dall'utente
- **App su misura** (non EasyEffects): finestra propria in Python + Qt (PySide6, già nella live), nome e grafica propri senza marchio Dolby, schema approvato: pulsanti Dinamico / Film / Musica / Spento; interruttori e cursori per surround virtuale, dialoghi, volume uniforme, equalizzatore con preset e bande, volume massimo +6 dB; filtro "Profili" messo prima di "Altoparlanti potenziati".
- **Motore: gli algoritmi Dolby originali**, non equivalenti aperti. Strada da valutare: ospitare su Fedora i DLL Dolby del Windows di questo portatile (uso personale sullo stesso hardware con licenza; niente modifiche ai binari, niente aggiramento di controlli).

### Fatto
- Inventario: pacchetto `dax3_swc_aposvc_arm64` (DAX3API.exe, DolbyDax3Apo.dll, DolbyAPOv251/v2100/vlldp*/VR, Dax3DapControl, Dax3Ref, DAXSSID, CaptureStreamMonitor), `dax3_ext_qc` (taratura del portatile `AUCD_DEV_0C29_SUBSYS_IDEA4001_…xml`, impostazioni Lenovo). Profili degli altoparlanti nella taratura: dynamic, movie, music, off (91 parametri ciascuno). Nessuna app Dolby Access installata in Windows.
- Lanciati 10 agenti di studio (modello "opus": lo strumento non permette di fissare la versione). Rapporti attesi in `repo/strumenti/audio-auto/dolby/`: `01-architettura`, `02-interfaccia-apo`, `03-dipendenze`, `04-servizio`, `05-attivazione`, `06-nucleo`, `07-taratura` (+ `taratura-yoga.json`, `tools/re-audio/dolby_taratura.py`), `08-lavoro-pubblico`, `09-esecuzione-dll`, `10-integrazione-app`.
- Materiali condivisi nello scratchpad (si perdono al riavvio; si rifanno con `objdump -d/-x` e `strings` sui file del DriverStore): `dolby/bin`, `dolby/dis`, `dolby/pkg`. Installati nella live: `hivex`, `rizin`.

### Prossimi passi
1. Leggere i 10 rapporti, scrivere la sintesi e il documento di progetto (motore + app), farlo approvare all'utente.
2. Piano di realizzazione, poi costruzione a passi con verifica.
3. I binari Dolby non vanno messi nel repo pubblico: il kit li prende dal Windows del portatile, come i firmware.

### Aggiornamento del punto 22 (17/11, ore 11:00 circa): progetto approvato, il codice Dolby gira su Fedora
- **Studio chiuso**: 10 rapporti in `repo/strumenti/audio-auto/dolby/` (`01`…`10`), taratura in `taratura-yoga.json` (10 profili, 130 parametri), dati in `dati/` (impronte dei DLL, proprietà dell'endpoint). Sugli altoparlanti lavorano `DolbyAPOVR.dll` (contenuti) e `DolbyAPOvlldp150.dll` (altoparlante), versione 3.30812.891.0; nessun controllo di licenza nei DLL di elaborazione; il servizio non serve. In Windows è sempre attivo il profilo Musica.
- **Progetto approvato dall'utente** (`PROGETTO.md`): ponte nativo che carica i due DLL originali dentro un filtro PipeWire prima di "Altoparlanti potenziati"; sei profili (Dinamico, Film, Musica, Gioco, Voce, Spento), Musica predefinito, equalizzatore a 20 bande, icona nel vassoio; file Dolby mai modificati né pubblicati.
- **Piano 1** (`PIANO-1-motore-a-file.md`), sorgenti in `repo/strumenti/audio/dolby/`:
  - Compito 1 FATTO: `pe.c`/`pe.h` caricano il DLL così com'è (impronta verificata, rilocazioni, funzioni importate collegate per nome con trappola per quelle non fornite; x18 puntato a un blocco fittizio). `./prova1` → OK (stato 30 791 byte, lavoro 8 378 byte).
  - Compito 2 FATTO: `vlldp.c` crea la libreria dell'altoparlante ed elabora blocchi da 256. `./prova2` → OK: silenzio resta silenzio, impulso ripetibile, 1 kHz a −40 dBFS a 0 dB con i parametri predefiniti, ingresso non valido ripulito. Descrittore dei buffer: canali, passo, tipo 7 (float), puntatori (come nel gemello). L'interruttore a stato+0xC6C nasce a 0 (uscita muta) e va messo a 1: per ora scritto direttamente, il setter vero è da trovare.
  - Prossimo, compito 3: applicare i parametri `tuning-vlldp` del profilo (setter scalari in `06` §2.3; per i vettori servono le firme: nel gemello pid 5 `(stato, blob)`, pid 17 `(stato, n, gruppi**)`, pid 22 `(stato, n, valori*)`, pid 31 `(stato, valori*)`, poi una funzione "apply(stato, canali)"; per bande dell'ottimizzatore e soglie del regolatore va letta la funzione `0x1800322f0`). Prova: risposta in frequenza uguale alla curva del profilo entro 0,5 dB.
  - Per compilare: `make -C repo/strumenti/audio/dolby` (serve gcc); i DLL si passano come cartella (nello scratchpad `dolby/bin`, oppure dal DriverStore in `/mnt/win`).
- **Istruzione dell'utente (17/11)**: "una volta finito l'app pubblica pure su github". Remoto già configurato: `origin` = `github.com/mich-de/yoga-slim7x-linux`. Alla pubblicazione escludere i file Dolby e gli altri file proprietari o personali presi da Windows (firmware, ACDB, XML di taratura e derivati, `dati/`, numeri di serie nei rapporti dei profili colore) e dire all'utente che cosa resta fuori.

### Punto 22, ore 11:30 circa: FASE 1 CHIUSA, la curva del profilo Musica esce dal codice Dolby originale
- `./prova3 <DLL> <impronte> <profili.txt> music` → OK: con l'ottimizzatore spento 1 kHz esce a 0,00 dB; con la curva del profilo le 20 bande escono con i guadagni della taratura, scarto massimo 0,40 dB (47 Hz −1,91 su −2,00; 234 Hz +2,43 su +2,50; 19 688 Hz +0,87 su +0,88).
- Funzioni trovate e decodificate nel DLL dell'altoparlante (in `indirizzi.h`): bande dell'ottimizzatore `0x180019c78(stato, int32 guadagni[], n)` (fino a 160 = 8 canali × 20 bande, sedicesimi di dB, scalati per 1/2080); soglie del regolatore `0x18001c9b0(stato, a[20], b[20])` (quale sia la bassa e quale l'alta va provato misurando); bande isolate `0x18001c760(stato, v[20])`; accensione del compressore multibanda `0x18001af30(stato, valore)`. Tutte alzano un segno "da ricalcolare" a stato+1644 e l'elaborazione ricalcola da sola: non è servita nessuna funzione "apply".
- `profili.py` traduce `taratura-yoga.json` in `profili.txt` (una riga per parametro; contiene la taratura: non va pubblicato, si rigenera).
- Prossimo: resto del compito 3 (regolatore, compressore multibanda, stress, con prova a 200 Hz ad alto livello), poi compito 4 (`DolbyAPOVR.dll`: indirizzi di partenza in `06` §3.3, ruoli dedotti), compito 5 (`yogadolby` da WAV a WAV), poi i piani 2 (tempo reale), 3 (app), 4 (kit).

### Punto 22, ore 11:50 circa: parametri del regolatore e formato reale dei valori di Windows
- **Valori veri di Windows per il profilo Musica** (registro, proprietà `{5510c7ab-…}` dell'endpoint, in `dati/proprieta-endpoint-windows.txt`): pid 7 = `160` + 160 guadagni; pid 8 = `20` + 20 soglie alte + `20` + 20 soglie basse; pid 9 = `20` + 20 bande isolate; pid 17 = `2`, poi per ogni gruppo `6` + 6 valori; pid 22 = `8` + stress `288 288 0…`; pid 13 = 1, pid 23 = 16, pid 11 = 12, pid 16 = 1, pid 21 = 256, pid 15 = −80, pid 6 = 1, pid 3/4/10/14 = 0. Coincidono con l'XML: il servizio non li trasforma.
- **Firme verificate nel codice**: stress `0x18001c908(stato, n ≤ 8, valori*)` limitati a 0…288; distorsione, pendenza (0…16) e timbro `(stato, valore)`.
- **Ordine delle soglie**: `0x18001c9b0(stato, alte, basse)` (dedotto dall'ordine nel registro e dal comportamento). Misure con tono a 234 Hz, distorsione accesa, timbro 12, pendenza 16, stress 288: un ingresso a −3 dBFS esce a −11,3 (soglia alta della banda −11,6) e uno a −20 passa invariato; a 3 kHz −3 esce a −5,8. Con l'ordine inverso tutto veniva schiacciato a circa −22 dBFS.
- **Aperto**: come Windows lega stress e guadagno di sistema al volume (il servizio reagisce al volume: da leggere in `DAX3API.exe`); effetto del compressore multibanda con l'ordine giusto delle soglie; `esplora4.c` è lo strumento per queste misure.

### Punto 22, ore 12:20 circa: AUDIO YOGA VERSIONE 1 FUNZIONA (motore dell'altoparlante, tempo reale, app, kit)
- **Fatto e provato**:
  - `motore.c`: sei profili della taratura applicati al DLL dell'altoparlante (curva, regolatore, compressore multibanda, stress, guadagni). Livelli misurati per profilo in `esplora5` (Musica: 234 Hz a −40 → −35,6; a −3 → −18; Spento: tutto invariato).
  - `audio_yoga_ladspa.c` → `audio_yoga.so`: plugin con porte Profilo (0…5), Spinta (dB), EQ 1…20; blocchi irregolari gestiti con ritardo costante; senza file privati passa invariato. `./prova_plugin` → OK.
  - `audio-yoga.conf` + `audio-yoga.service` (servizio utente separato: quello dei filtri di serie vieta la memoria eseguibile). `prove/prova_pipewire.sh` → OK su un'uscita finta (Musica −35,6 dB, Spento −40,0 dB).
  - `audio_yoga.py` (PySide6): sei profili, volume massimo, equalizzatore a 20 bande con curve Piatto / Dettagliato / Caldo ricavate dalla taratura, icona nel vassoio, stato in `~/.config/audio-yoga/stato.json`; i tre effetti del secondo DLL sono mostrati come "in arrivo". Prova con `--prova`: i parametri del filtro cambiano davvero.
  - Kit: `avvio/audio-yoga.sh` (installa plugin, configurazione, servizio, app, voce di menu, avvio automatico; copia il DLL dal Windows del portatile se manca), richiamato da `autorun-root.sh` e `dopo-anaconda.sh`; `utente-login.sh` sceglie "Audio Yoga" come uscita predefinita se c'è. File privati sulla chiavetta in `STRUMENTI/dolby-privato/` (DLL, impronte, `profili.txt`). Plugin compilato in `STRUMENTI/audio/dolby/audio_yoga.so`.
- **Stato della sessione live**: servizio attivo, "Audio Yoga" uscita predefinita (profilo Musica), app aperta. Per tornare a prima: scegliere "Altoparlanti potenziati" come uscita.
- **Limiti noti**: mancano gli effetti di `DolbyAPOVR.dll` (surround, dialoghi, livellatore, volume massimo vero: quello attuale usa il guadagno di sistema della libreria dell'altoparlante); il volume di sistema agisce prima del motore (in Windows dopo); il legame fra volume e stress del regolatore non è riprodotto; l'interruttore a stato+0xC6C è scritto direttamente; in `autorun-root.sh` la copia del DLL da Windows avviene prima dell'apertura di BitLocker (oggi il DLL è già sulla chiavetta); l'avvio a freddo con queste novità non è provato.
- **Prossimi passi**: 1) `DolbyAPOVR.dll` (compito 4 del piano: indirizzi di partenza in `06` §3.3, da confermare; modello nel gemello `sp11_dolby_windows_chain_ladspa.c`); 2) attivare nell'app i tre effetti; 3) riavvio di verifica; 4) pubblicazione su GitHub quando l'app è completa (istruzione dell'utente), escludendo file Dolby, taratura e derivati, firmware, ACDB, `dati/`, numeri di serie.

### Punto 22, ore 13:00 circa: AUDIO YOGA COMPLETO (i due DLL Dolby), commit pronto, manca solo l'accesso a GitHub
- **Secondo DLL integrato**: `DolbyAPOVR.dll` (libreria dei contenuti, dap_vr) gira su Fedora come il primo. Sequenza ricavata dal codice del DLL: configurazione di 64 byte con la sola frequenza, `query_memory` `0x180038178`, `init` `0x180036d98`, `query_scratch` `0x1800385d8`, `output_mode_set` `0x180037b50(stato, modo, canali, matrice)`, `prepare` `0x180037d20(stato, 1, ingresso, zeri…)` che ritorna il numero di canali, `process` `0x18003e068(stato, uscita, lavoro)` con risultato per indirizzo (x8). Parametri a un valore: tabella del rapporto `06` §2.2 (in `motore.c`). Sorgenti: `vr.c`, `vr.h`; in `pe.c` la chiamata con argomenti sullo stack `win_chiama_zeri`.
- **Misure** (`esplora_vr2`, `esplora5`): nel profilo Musica il secondo DLL è trasparente (per questo la versione 1 suonava già come Windows); modo 11 + decodifica surround porta un segnale del solo canale sinistro anche a destra (−41 dB) e alza 1 kHz di 1,8 dB; il livellatore a 7 porta un tono da −40 a −20,8 dBFS; con i tre effetti spenti Dinamico esce invariato. `volmax-boost` da solo non cambia il livello: il "Volume massimo" dell'app resta il guadagno di sistema della libreria dell'altoparlante (+6 dB, trattenuto dal regolatore).
- **Sul Yoga il surround virtuale vale anche per l'audio stereo**: nelle impostazioni Lenovo `bypass_stereo_virtualizer` è falso per tutti i profili (sul Surface è vero). Dinamico, Film e Gioco usano il modo 11.
- **Plugin e app**: porte nuove `Surround` (−1 come il profilo, 0, 1), `Dialoghi` (−1, 0, 1…16), `Livellatore` (−1, 0, 1…10); l'app mostra per ogni profilo i valori della taratura (Dinamico e Film: surround e dialoghi 5; Gioco: surround; Voce: dialoghi 8) e permette di cambiarli. Ritardo totale 690 campioni (14 ms). Prove: `./prova_plugin` con `CON_CONTENUTI=1`, `prove/prova_pipewire.sh`, app con `--prova`: tutte OK.
- **Installato nella live e sulla chiavetta** (`STRUMENTI/dolby-privato/` ora ha i due DLL). Servizio attivo, uscita predefinita Audio Yoga, app aperta.
- **Pubblicazione**: il repository `mich-de/yoga-slim7x-linux` è privato; il token di `gh` in questa live non è valido, quindi il push non è stato possibile. Commit fatto sul ramo `audio-yoga` (85 file; fuori dal commit: taratura e derivati, registro, profili colore, firmware nell'initrd e i due `strumenti.cpio` che ora lo contengono, tarature della protezione; regole in `.gitignore`). Per pubblicare: `gh auth login -h github.com`, poi `git -C repo push -u origin audio-yoga`.
- **Resta**: riavvio di verifica (avvio a freddo: punto 20 e Audio Yoga), push dopo l'accesso, giudizio a orecchio dell'utente, lavoro sugli amplificatori (punto 21).

### Punto 22, ore 14:40: pubblicato su GitHub (ramo `audio-yoga`)
Accesso `gh` rifatto dall'utente (codice nel browser; due tentativi falliti per una caduta del Wi-Fi). `git push -u origin audio-yoga` riuscito: `origin/audio-yoga` = `400b6e7`, quattro commit avanti a `origin/main` (i tre che `main` locale aveva già e quello di Audio Yoga). Repository privato, ramo predefinito `main`: per vedere il lavoro nella pagina principale va unito `audio-yoga` in `main` (decisione dell'utente). Verificato anche che il servizio vero ha i due DLL caricati (tre zone di memoria eseguibile nel processo). Lo stato dell'app al momento: profilo Spento, volume massimo ed equalizzatore "Caldo" scelti dall'utente.

Ore 14:45: con il sì dell'utente `main` è stato portato a `838a074` (avanzamento semplice) e pubblicato: `origin/main` = `origin/audio-yoga`. Fuori dal repository restano i due `strumenti.cpio` modificati (contengono firmware) e i dati privati elencati in `.gitignore`.

### Punto 22, ore 15:10: "non sento cambiamenti" → causa trovata e corretta (la catena a valle appiattiva tutto)
- **Sintomo** (utente): cambiando profilo e comandi nell'app non si sentiva nessuna differenza.
- **Misure sulla catena vera** (rumore rosa a −20 dBFS, registrando l'ingresso e l'uscita di "Altoparlanti potenziati"): il filtro Audio Yoga cambiava il segnale (da −19,2 dB con Spento a −12,0 con Musica + volume massimo; con Dinamico correlazione fra i canali −0,61), ma all'uscita verso gli altoparlanti i quattro casi stavano entro 0,4 dB. Il compressore 3:1 con +12 dB e il limitatore con +6 dB di "Altoparlanti potenziati", messi per compensare l'amplificatore debole, tenevano tutto al tetto digitale.
- **Correzione**: `avvio/audio-yoga.sh` genera `/etc/pipewire/filter-chain.conf.d/52-yoga-altoparlanti-ay.conf`, una copia della catena degli altoparlanti per Audio Yoga ("Altoparlanti (via Audio Yoga)", nodo `effect_input.yoga_spk_ay`) con rapporto del compressore 1:1, guadagno fisso +6 dB (con +12 era ancora al tetto), guadagno d'ingresso del limitatore 0 e limitatore dei bassi alzato da −9 a −1,5 dBFS (imitava il regolatore Dolby, che ora c'è davvero). `audio-yoga.conf` manda lì l'uscita; "Altoparlanti potenziati" resta com'era per chi lo sceglie direttamente.
- **Dopo la correzione**: uscita finale dei woofer −22,6 dB con Spento, −16,9 con Musica + volume massimo, −16,7 con Dinamico: le differenze passano. `prove/prova_pipewire.sh` → OK.
- **Limite che resta**: con gli amplificatori a 18/16 il tetto digitale è vicino; a volume pieno con musica forte il limitatore a −1,5 dBFS schiaccia ancora. Il volume vero come in Windows richiede gli amplificatori a 18 dB con la protezione (punto 21).
- Strumenti di misura usati: scratchpad `misura/` (rumore rosa, `analizza.py`); per rifarli: `pw-record --target <nodo> -P stream.capture.sink=true`.
