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
