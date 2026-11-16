# Altre distro sul Lenovo Yoga Slim 7x (83ED, Snapdragon X Elite)

Cosa serve a qualsiasi distro Linux su questo portatile, e cosa c'è già in questo kit.
Fatti verificati il 2026-11-16 su sorgenti del kernel, linux-firmware, ISO di Fedora 45 e Windows di questa macchina.

## 1. Requisiti comuni

| Cosa | Dettaglio | Nel kit |
|---|---|---|
| Architettura | Solo immagini **aarch64/arm64**. Le ISO x86_64 non partono. | — |
| Avvio da USB | Scrivere la ISO "raw" sulla chiavetta. Ventoy: la modalità GRUB2 non carica i kernel ARM64 recenti, e con Secure Boot attivo non parte. | `windows/scrivi-iso-su-usb.ps1` |
| Device tree | `x1e80100-lenovo-yoga-slim7x.dtb` (model "Lenovo Yoga Slim 7x"). Fedora 44+ e Ubuntu lo scelgono da soli; altre distro lo vogliono indicato nel bootloader (`devicetree` in GRUB/systemd-boot). Deve essere quello del kernel in uso. | `dtb/` (dal kernel 7.2.11 di Fedora) |
| Parametri kernel | `clk_ignore_unused pd_ignore_unused` sempre. Per avviare **da USB-C**: `modprobe.blacklist=qcom_q6v5_pas` (altrimenti il riavvio del coprocessore ADSP stacca la chiavetta). Su systemd: `systemd.tpm2_wait=0` evita 90 s di attesa. | `boot/LEGGIMI.txt` |
| Firmware | In `/lib/firmware/qcom/x1e80100/LENOVO/83ED/`: `qcadsp8380.mbn`, `adsp_dtbs.elf`, `adsp*.jsn`, `battmgr.jsn` (audio e batteria), `qccdsp8380.mbn`, `cdsp_dtbs.elf`, `cdspr.jsn`, `qcdxkmsuc8380.mbn` (GPU), `qcvss8380.mbn` (video). linux-firmware recente li include; qui c'è la versione più nuova presa da Windows. Devono stare anche nell'initramfs. | `firmware/` + `8-INSTALLA-FIRMWARE.sh` |
| GPU | `qcom/gen70500_sqe.fw`, `qcom/gen70500_gmu.bin` da linux-firmware; Mesa recente (driver freedreno/turnip). | — |
| Wi-Fi / Bluetooth | ath12k WCN7850 (`ath12k/WCN7850/hw2.0/`) e `qca/hmtbtfw20.tlv` da linux-firmware. | — |
| Audio | Scheda `X1E80100-LENOVO-Yoga-Slim7x`: topologia `qcom/x1e80100/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin`, profilo UCM `ucm2/Qualcomm/x1e80100/Slim7x-HiFi.conf` (alsa-ucm-conf recente), PipeWire + WirePlumber, ADSP in esecuzione. | `firmware/`, `ucm/`, `11-AUDIO-BASE-FEDORA.sh` |
| Audio: volume | Misurato nella live Fedora (kernel 7.2.11): nel PCM a 4 canali i canali 0,1 sono i woofer e 2,3 i tweeter; con audio stereo i tweeter restano muti. Inoltre il controllo `PA Volume` degli amplificatori WSA884x non ha effetto (bit `CSR_GAIN_EN` mai impostato dal driver). In Linux manca la protezione degli altoparlanti di Windows: prudenza con i guadagni. | `6-AUDIO-PIU-FORTE.sh` (PipeWire filter-chain, serve `ladspa-swh-plugins`), `7-VOLUME-AMPLIFICATORI.sh` + `audio/wsagain.c` (modulo da ricompilare per ogni kernel) |
| **Tastiera e touchpad** | **Problema specifico di questo portatile (BIOS NHCN62WW), vale per ogni distro.** Controller tastiera ITE `048D:8987` (I2C 0x3a) e touchpad ELAN `04F3:3303` (0x2c) stanno sullo stesso bus (`i2c0`, nodo `/soc@0/geniqup@bc0000/i2c@b80000`). Con i 400 kHz del device tree ufficiale la tastiera restituisce dati corrotti, blocca la linea SDA e ferma anche il touchpad (`i2c_hid_of …-003a: failed to change power setting`, errori `-110`). **Rimedio: `clock-frequency = <100000>` su quel bus.** Provato a caldo il 16/11 nella live Fedora. Driver: `i2c_hid_of` + `hid_lenovo`. | `tools/patch-dtb-i2c100k.py` (qualsiasi kernel con device tree incorporati o file .dtb), `fix-tastiera/`, `5-FIX-TASTIERA-SUBITO.sh`, `12-TASTIERA-FIX-PERMANENTE.sh`, `upstream/` |
| Touchscreen | HID su I2C (0x14 su i2c8): funziona senza interventi. | — |
| Embedded controller | Il nodo EC (`lenovo,yoga-slim7x-ec`: ventola, sensori, sospensione) è entrato nel kernel a luglio 2026; a settembre 2026 il GPIO 65 (reset dell'EC) è stato marcato riservato perché "su alcuni dispositivi, toccare la linea di reset dell'EC impedisce l'accensione finché non si stacca la batteria". **Non manipolare il GPIO 65.** Il kernel 7.2.11 della ISO Fedora 45 non ha nessuna delle due modifiche: preferire kernel più recenti. | — |
| Secure Boot | Vedi `secureboot/LEGGIMI.txt`. | `secureboot/`, `windows/` |
| Windows | Tenerlo in dual boot: serve per aggiornare BIOS e firmware. | — |

## 2. Distro

| Distro | Stato per questo modello | Note |
|---|---|---|
| **Fedora 45** (KDE/Workstation aarch64) | Supportato con i passi della guida ufficiale. Kernel ISO 7.2.11; negli aggiornamenti c'è 7.3.3. | Guida: https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install · modello: https://fedoraproject.org/wiki/Yoga_Slim7x · script `6-DOPO-INSTALLAZIONE-FEDORA.sh` |
| **Ubuntu 26.04 LTS / 26.10** (desktop arm64) | ISO ufficiali esistenti: https://cdimage.ubuntu.com/releases/26.04/release/ e https://cdimage.ubuntu.com/releases/26.10/release/ . Supporto X Elite documentato dalla community; **non provato qui**. | Firmware: pacchetto `qcom-firmware-extract` oppure `8-INSTALLA-FIRMWARE.sh` (riconosce `update-initramfs`). FAQ: https://discourse.ubuntu.com/t/faq-ubuntu-25-04-on-snapdragon-x-elite/61016 |
| **Debian** (testing) | Da verificare: https://wiki.debian.org/InstallingDebianOn/Qualcomm/KnownIssues | Stessi requisiti; `8-INSTALLA-FIRMWARE.sh` usa `update-initramfs`. |
| **Arch Linux ARM / derivate** (Omarchy ARM compreso) | Non supportano ufficialmente gli Snapdragon X: kernel e device tree vanno gestiti a mano. Omarchy 4.5 ARM dichiara supporto solo per NVIDIA DGX Spark e N1X. | Appunti di un utente per questo modello: https://gist.github.com/joske/52be3f1e5d0239706cd5a4252606644b · `8-INSTALLA-FIRMWARE.sh` usa `mkinitcpio`. |
| Kernel di comunità | Albero con patch per portatili X Elite (pacchetti .deb): https://github.com/jglathe/linux_ms_dev_kit | Utile se il kernel della distro è troppo vecchio. |

## 3. Procedura generica per provare una distro

1. Scarica la ISO **arm64** e controlla lo SHA-256 dal sito della distro.
2. Windows, PowerShell amministratore: `windows\scrivi-iso-su-usb.ps1 -Iso … -Disco N -Modello … -Conferma` (cancella la chiavetta; questa partizione STRUMENTI verrebbe persa se scrivi sullo stesso disco: usa un'altra chiavetta o ricopia la cartella).
3. Secure Boot disattivato, F12, avvia. Nel menu della distro premi `e` e aggiungi alla riga `linux` i parametri del punto 1 (tastiera americana nel menu: `_` = Maiusc + `'`, `=` = `ì`).
4. Tastiera: aspettati che NON funzioni finché il bus I2C non è a 100 kHz. Servono una tastiera USB/Bluetooth o la tastiera a schermo per i primi passi. Poi correggi il kernel o il .dtb della distro con `python3 tools/patch-dtb-i2c100k.py` (per i kernel con device tree incorporati: copia corretta del kernel e voce di avvio che la usa; per i .dtb separati: `devicetree` nel bootloader). Il modulo `fix-tastiera/i2cslow2.ko` vale solo per il kernel 7.2.11-300.fc45 di Fedora (sorgente incluso).
5. Nella live: `sudo bash 1-DIAGNOSTICA.sh` da questa cartella per vedere cosa funziona.
6. Dopo l'installazione: `sudo bash 8-INSTALLA-FIRMWARE.sh`, togli la blacklist di `qcom_q6v5_pas` dai parametri del kernel, riavvia. Audio: `sudo bash 11-AUDIO-BASE-FEDORA.sh` (i passi solo-Fedora vengono saltati), poi `6-AUDIO-PIU-FORTE.sh`.
