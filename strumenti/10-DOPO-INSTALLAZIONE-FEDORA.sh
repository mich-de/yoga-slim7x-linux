#!/bin/bash
# Da eseguire UNA volta su Fedora appena installata sul Yoga Slim 7x (non nella live).
# Applica i passi della guida Fedora "Snapdragon_WoA_Laptop_Install", poi tastiera, firmware e audio.
#   https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install
# Se la tastiera non va ancora: tastiera USB/Bluetooth o tastiera a schermo per lanciarlo
# (oppure, meglio, dalla live prima di riavviare:  sudo bash 12-TASTIERA-FIX-PERMANENTE.sh --dalla-live).
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/dopo-installazione-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
log "=== Dopo installazione $(date) - $(modello) - kernel $(uname -r)"
if is_live; then log "Questa e' la sessione live: esegui questo script dopo aver installato e riavviato."; exit 1; fi
command -v grubby >/dev/null || log "ATTENZIONE: grubby non trovato (non sembra Fedora): i parametri del kernel vanno messi a mano."

log "--- 1. Tastiera e touchpad: bus I2C a 100 kHz su tutti i kernel installati"
bash "$KIT/12-TASTIERA-FIX-PERMANENTE.sh" --auto 2>&1 | tee -a "$L"

log "--- 2. Tolgo la blacklist lasciata dall'installer (serviva solo per avviare da USB)"
rm -f /etc/modprobe.d/anaconda-denylist.conf && log "ok"

log "--- 3. Modulo scmi-cpufreq (regolazione della frequenza della CPU)"
echo scmi-cpufreq > /etc/modules-load.d/scmi-cpufreq.conf && log "ok"

log "--- 4. Parametri del kernel"
if command -v grubby >/dev/null; then
    grubby --update-kernel=ALL --args="systemd.tpm2_wait=0 clk_ignore_unused pd_ignore_unused" >> "$L" 2>&1
    grubby --update-kernel=ALL --remove-args="modprobe.blacklist=qcom_q6v5_pas module_blacklist=qcom_q6v5_pas" >> "$L" 2>&1
    grubby --info=DEFAULT 2>/dev/null | grep -E '^(kernel|args)' | tee -a "$L"
fi

log "--- 5. Firmware e audio di base"
bash "$KIT/11-AUDIO-BASE-FEDORA.sh" --auto 2>&1 | tee -a "$L"

log "--- 6. Prossimi passi"
log "a) Volume degli altoparlanti (da utente normale, poi come root):"
log "     bash 6-AUDIO-PIU-FORTE.sh          uscita 'Altoparlanti potenziati' (fa suonare anche i tweeter)"
log "     sudo bash 7-VOLUME-AMPLIFICATORI.sh   guadagno degli amplificatori (leggi le avvertenze nello script)"
log "b) sudo dnf upgrade --refresh   (kernel piu' recente del 7.2.11; l'aggancio del punto 1 corregge anche i nuovi kernel)."
log "   I moduli fix-tastiera/i2cslow2.ko e audio/wsagain.ko valgono SOLO per il kernel 7.2.11-300.fc45:"
log "   dopo un aggiornamento del kernel wsagain va ricompilato (istruzioni in 7-VOLUME-AMPLIFICATORI.sh)."
log "c) Riavvia."
sync
popup "Dopo-installazione completato: riavvia il portatile" 10
