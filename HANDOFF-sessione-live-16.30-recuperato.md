<!-- Recuperato il 2026-11-16 dai settori grezzi della partizione STRUMENTI: e' il HANDOFF scritto dalla sessione fatta nella live Fedora (aggiornato 16:30), sovrascritto per errore dalla sessione Windows. Testo non modificato. -->
# HANDOFF — Fedora su Lenovo Yoga Slim 7x (aggiornato 2026-11-16 16:30)

Copia di questo file: `D:\linux\HANDOFF.md` (Windows) e nella ESP della chiavetta Transcend (`/mnt/HANDOFF.md` dalla live).

## Continuare da Fedora live (senza Windows)
1. Avvia la chiavetta Transcend (F12) → voce **"Start Fedora-KDE-Live - Yoga Slim 7x (X1E)"** (default).
2. Tastiera interna NON funziona in live: usa tastiera virtuale KDE (o tastiera USB via hub).
3. Collega il Wi-Fi dall'icona di rete.
4. Konsole:
   ```
   sudo mount -o loop,offset=3508396032 /dev/sda /mnt
   curl -fsSL https://claude.ai/install.sh | bash
   cd /mnt && ~/.local/bin/claude
   ```
   Poi: "leggi HANDOFF.md e riprendi". La live non è persistente: al riavvio Claude Code va reinstallato.
5. Diagnostica senza Claude: `sudo sh /mnt/diag.sh` → crea `riepilogo-*.txt` e `diag-*.txt` in /mnt (ESP chiavetta) e stampa il riepilogo [OK]/[KO].

**Novità**: sul Transcend c'è la partizione 3 **STRUMENTI** (FAT32 4 GB, offset 3539992576, dopo la ISO) visibile in Dolphin → Dispositivi. Contiene `1-DIAGNOSTICA.sh`, `2-PROVA-FIX-TASTIERA.sh` (unbind/bind i2c_hid_of), `3-SOSPENSIONE-TEST.sh` (rtcwake 10 s), `4-CLAUDE-CODE.sh`, `HANDOFF.md`, `LEGGIMI.txt`. Doppio clic → Esegui: si aprono in Konsole e diventano root; log e esiti restano in STRUMENTI (in Windows lettera Y:).

## 1. Obiettivo
Fedora 45 KDE Plasma aarch64 in dual boot con Windows; alla fine Secure Boot abilitato.

## 2. Hardware e stato
- Laptop: Lenovo Yoga Slim 7x 14Q8X9 (MT 83ED), Snapdragon X Elite X1E78100, Adreno X1-85, 32 GB, BIOS NHCN62WW, Windows 11 ARM64.
- Dischi: interno Samsung NVMe 1 TB (Windows C: + dati D:). Chiavetta install = **Transcend TS256GSS 256 GB** in adattatore **JMicron 152D:0567** (l'adattatore ASMedia 174C:55AA dava reset UAS: non usarlo).
- Chiavetta: ISO `Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso` scritta raw, sha256 verificato `46a73d4c0a82a77551311ab1589255ecac51b5ce311b4fc84577f5ede5a44f5c`. Partizione 2 = ESP FAT 30 MB a offset **3508396032**: contiene `EFI/BOOT/grub.cfg` personalizzato (originale in `grub.cfg.orig`), `diag.sh`, `HANDOFF.md`.
- Menu GRUB: voce default con `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0 modprobe.blacklist=qcom_q6v5_pas` (senza blacklist il reset ADSP scollega la chiavetta USB-C → dracut timeout). "Test this media" rimosso.
- Firmware: Secure Boot **Disabled**, Setup Mode / Custom, PK/KEK/db **vuoti** (Reset to Setup Mode). Ritorno a fabbrica: BIOS → Security → Restore Factory Keys. BitLocker C: protezione disattivata.
- Live: avvia, display/touchpad/touchscreen OK; **tastiera interna KO** (anche voce originale). In live atteso KO anche audio/batteria (ADSP disattivato).

## 3. Tastiera + touchpad — RISOLTO a caldo il 16/11 (da confermare al prossimo boot)
- **Confermato dall'utente (16/11)**: dopo il fix a caldo la tastiera interna scrive e il touchpad funziona.
- **Causa**: il controller tastiera ITE 048D:8987 (@0x3a su b80000.i2c / i2c-1, condiviso col touchpad ELAN 04F3:3303 @0x2c) su questa macchina (BIOS NHCN62WW) **non regge i 400 kHz del DTB upstream**: dopo 16 byte perde un bit, il descrittore HID arriva troncato (wCommandRegister letto 0xFF11 invece di 0x0022), il driver scrive su un registro sbagliato, la tastiera resta a metà transazione e tiene **SDA (GPIO0) bassa** → bus morto, anche il touchpad va in timeout (-110). In bit-bang lento il descrittore è corretto.
- **Fix**: `clock-frequency = <100000>` sul nodo `/soc@0/geniqup@bc0000/i2c@b80000`. Verificato a caldo: compaiono `hid-over-i2c 048D:8987 Keyboard` (driver lenovo) e `04F3:3303 Touchpad`, bus stabile. Resta solo un innocuo "device did not ack reset within 1000 ms".
- **Chiavetta**: nuova voce GRUB di default **"... + FIX TASTIERA (I2C 100 kHz)"** che carica `EFI/BOOT/yoga7x-kbd100k.dtb` (DTB del kernel 7.2.11-300.fc45 con la sola modifica sopra) col comando `devicetree`. NON ancora provata al boot: se desse problemi usare la seconda voce (senza fix) e poi `5-FIX-TASTIERA-SUBITO.sh`. Backup: `grub.cfg.bak-1530`, `grub.cfg.bak-1600`.
- **Senza riavvio**: `STRUMENTI/5-FIX-TASTIERA-SUBITO.sh` = insmod `fix-tastiera/i2cslow2.ko` (sostituisce in RAM la property clock-frequency; solo kernel 7.2.11-300.fc45, sorgente `i2cslow2.c`: per ricompilare `dnf install gcc make kernel-devel-$(uname -r)`), bus recovery via gpioset (impulsi SCL finché SDA=1, poi STOP), rebind `geni_i2c`. Attenzione: la property DT sta in memoria read-only, va sostituito il puntatore `prop->value`, non scritto il valore.
- **Sistema installato**: il DTB va ripatchato a ogni aggiornamento kernel (`fdtput -t u <dtb> /soc@0/geniqup@bc0000/i2c@b80000 clock-frequency 100000`, poi `devicetree` in GRUB / `GRUB_DEFAULT_DTB`), finché non c'è un fix upstream → segnalare a linux-arm-msm (x1e80100-lenovo-yoga-slim7x.dts).
- I vecchi esiti "FUNZIONA" di script 2/3 e "[OK] Tastiera/Touchpad" di diag erano falsi positivi (tastiera Bluetooth iClever; controllo solo sul nome). Lo script 2 (rebind i2c_hid_of) è inutile.

- **Upstream (da inviare)**: `STRUMENTI/upstream/segnalazione-linux-arm-msm.txt` + patch RFC `0001-*.patch` (firma OdissREA). Prima dell'invio: conferma a freddo della voce GRUB "FIX TASTIERA", possibilmente prova a 200 kHz. Invio in testo semplice (git send-email o Gmail in plain text), mai senza approvazione dell'utente.

## 3b. Audio altoparlanti (limite noto)
- Volume basso = tetto di sicurezza del kernel (WSA_RXn Digital Volume max 81, PA Volume max 6): Linux non ha la speaker protection di Windows (ADSP + VI sense + calibrazione Lenovo). Sulla scheda ci sono i VISENSE Switch ma nessun PCM di cattura VI, e mancano i parametri degli altoparlanti → **non alzare il tetto**.
- **Scoperta 16/11 (misurata con i microfoni interni, toni su un canale alla volta)**: nel PCM a 4 canali i canali 0,1 (FL,FR) sono i **woofer**, i canali 2,3 (RL,RR) i **tweeter**. PipeWire con audio stereo riempie solo FL/FR → **i tweeter restano muti**: è la causa principale del suono basso e cupo. (Possibile segnalazione a alsa-ucm-conf / PipeWire, non ancora fatta.)
- Rimedio installato: `6-AUDIO-PIU-FORTE.sh` → sink stereo PipeWire "Altoparlanti potenziati" (`audio/50-yoga-altoparlanti.conf` in `~/.config/pipewire/filter-chain.conf.d/`, `filter-chain.service` utente, richiede `ladspa-swh-plugins`): passa-alto 110 Hz → compressore sc4 (soglia -24 dBFS, 3:1, +12 dB) → limitatore -1,5 dBFS → crossover LR4 a 3 kHz: woofer passa-basso, tweeter passa-alto a -6 dB con **polarità invertita** (senza inversione c'è un buco a 3 kHz). Misura ai microfoni con multitono: livello totale +13 dB rispetto all'uscita diretta, acuti 6–10 kHz +18/+30 dB. Regolazione finale 16/11: compressore RMS puro (attacco 5 ms, rilascio 200 ms), limitatore con +6 dB in ingresso e rilascio 50 ms, tweeter a -9 dB invertiti. Con segnale tipo musica (RMS -15,5 dBFS, picchi -4): woofer da -15,5 a -13,2 dBFS RMS, microfoni da -38 a -26 dBFS (il grosso viene dai tweeter); caso peggiore sinusoide a fondo scala: -4,6 dBFS RMS (meno dell'uscita diretta). **Oltre non si va senza alzare il tetto del kernel** (PA Volume bloccato a 6 = 0 dB su scala da -9 dB a passi di 1,5 dB; Digital Volume 81 su 84): l'utente trova il volume ancora basso. Tetto del kernel non toccato. Da rilanciare dopo ogni boot della live e dopo l'installazione. Rimozione: `systemctl --user disable --now filter-chain`. Con le cuffie scegliere a mano l'uscita cuffie.

- **Scoperta 16/11 sera — il vero motivo del volume basso**: il controllo `* PA Volume` degli amplificatori WSA884x è **inerte** (misurato: a 3, 6, 8, 10 stesso livello ai microfoni). Nel driver mainline (sound/soc/codecs/wsa884x.c, v7.2.11) il bit `CSR_GAIN_EN` (bit 0 di DRE_CTL_1, reg 0x34b1) non viene mai impostato (letto 0x2a via debugfs regmap) e i compander della WSA macro sono spenti da UCM (`WSA_COMP1/2 Switch` = 0): gli amplificatori restano al guadagno automatico minimo. Il tetto del kernel su PA Volume quindi non c'entra.
- Preparato ma **NON caricato** (bloccato dal controllo permessi di Claude Code, serve decisione esplicita dell'utente): `scratchpad/wg/wsagain.c` = modulo che imposta CSR_GAIN_EN sugli amplificatori (parametri `en`, `cap`, `only`) per rendere attivo PA Volume; piano: calibrare a passi con tono 700 Hz a -12 dBFS e microfoni, partendo da PA=0, fino a +6 dB woofer / +3 dB tweeter rispetto a oggi (scelta dell'utente). Scala reale del registro non verificata (downstream Qualcomm: reg 0 = +21 dB, passi da 1,5 dB — a memoria). Rischio altoparlanti: nessuna protezione.
- Stato attuale: modulo `spkcap` caricato (tetto PA a 10, senza effetto udibile), PA Volume woofer=10 tweeter=8 (inerti). Copia di `spkcap.c/.ko` in `audio/`.
- Driver Windows: la pagina Lenovo del modello NON offre il driver audio (solo BIOS, diagnostica, X-Rite); arriva da Windows Update. La copia in `D:\Driver_Lenovo_Yoga_Slim_7_14Q8X9_83ED\export` non è leggibile dalla live (D: è BitLocker). Per studiarla: copiarne da Windows le cartelle audio (qcaud*, qcwsa*, *adsp*, *.acdb) in STRUMENTI.

## 4. Tentativi falliti / da evitare
- Ventoy: SB on → boot failed (non firmato su ARM64); GRUB2 mode (`_VTGRUB2`/`r`) → `invalid magic number` (kernel Fedora 45 PE senza magic ARM64). Normal mode funzionava, ma ora si usa la chiavetta raw.
- **`systemd.run=` nel cmdline blocca l'avvio** (sostituisce il target di default): non usarlo.
- Secure Boot: firmware di fabbrica senza Microsoft UEFI CA → nessun Linux firmato parte con SB on; BIOS senza "enroll from file".
- Windows: PowerShell elevato solo via script `.ps1` con `-File`; costante 0xC0000000 → usare `[uint32]3221225472`; `[math]::Min` con long → overflow Int32.
- Cartella `E:\Marco Maresca` (vecchio Kingston) sparita; recupero rifiutato.

## 5. Prossimi passi
1. Al prossimo boot verificare la voce GRUB "FIX TASTIERA" (tastiera+touchpad attivi subito).
2. Installazione dual boot da live (non toccare partizioni Windows; spazio da ridurre su D: o C:).
3. Post-install (wiki Fedora WoA): `sudo rm -f /etc/modprobe.d/anaconda-denylist.conf`; `echo scmi-cpufreq | sudo tee /etc/modules-load.d/scmi-cpufreq.conf`; `sudo grubby --update-kernel=ALL --args="systemd.tpm2_wait=0"`; `sudo dnf --enable-repo=updates-testing install qcom-firmware-extract && sudo qcom-firmware-extract`; `sudo dracut -f`.
   Firmware anche dall'export Windows `D:\Driver_Lenovo_Yoga_Slim_7_14Q8X9_83ED\export`: `qcsubsys_ext_adsp8380*\qcadsp8380.mbn`+`adsp_dtbs.elf`, `qcnspmcdm_ext_cdsp8380*\qccdsp8380.mbn`+`cdsp_dtbs.elf` → `/lib/firmware/qcom/x1e80100/LENOVO/83ED/`.
4. Secure Boot: in Fedora installata `sudo dnf install sbctl && sudo sbctl create-keys && sudo sbctl enroll-keys --microsoft` (verificare che includa Windows UEFI CA 2023, MS UEFI CA 2011/2023, KEK 2011 + KEK 2K 2023) → BIOS Secure Boot Enabled → verificare Windows e Fedora.

Fonti: https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install · https://fedoraproject.org/wiki/Yoga_Slim7x
