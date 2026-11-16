#!/bin/bash
# Da eseguire UNA volta su Fedora appena installata sul Yoga Slim 7x (non nella live).
# Applica i passi della guida Fedora "Snapdragon_WoA_Laptop_Install" e poi sistema firmware e audio.
#   https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/dopo-installazione-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
log "=== Dopo installazione $(date) - $(modello) - kernel $(uname -r)"
if is_live; then log "Questa e' la sessione live: esegui questo script dopo aver installato e riavviato."; exit 1; fi
command -v grubby >/dev/null || log "ATTENZIONE: grubby non trovato (non sembra Fedora): i parametri del kernel vanno messi a mano."

log "--- 1. Tolgo la blacklist lasciata dall'installer (serviva solo per avviare da USB)"
rm -f /etc/modprobe.d/anaconda-denylist.conf && log "ok"

log "--- 2. Modulo scmi-cpufreq (regolazione frequenza CPU)"
echo scmi-cpufreq > /etc/modules-load.d/scmi-cpufreq.conf && log "ok"

log "--- 3. Parametri del kernel"
if command -v grubby >/dev/null; then
    grubby --update-kernel=ALL --args="systemd.tpm2_wait=0 clk_ignore_unused pd_ignore_unused" >> "$L" 2>&1
    grubby --update-kernel=ALL --remove-args="modprobe.blacklist=qcom_q6v5_pas module_blacklist=qcom_q6v5_pas" >> "$L" 2>&1
    grubby --info=DEFAULT 2>/dev/null | grep -E '^(kernel|args)' | tee -a "$L"
fi

log "--- 4. Firmware e audio"
bash "$KIT/7-AUDIO-FIX-FEDORA.sh" --auto 2>&1 | tee -a "$L"

log "--- 5. Tastiera"
e=$(sed -n 's/^RIMEDIO=//p' "$LD/tastiera-ESITO.txt" 2>/dev/null | tail -n1)
case "$e" in
    rebind|generic) log "Dal test nella live il rimedio era '$e': lo rendo permanente."; bash "$KIT/2-TASTIERA-TEST-E-FIX.sh" --permanente --auto 2>&1 | tee -a "$L" ;;
    *) log "Nessun rimedio tastiera da applicare (esito salvato: ${e:-nessuno}). Se la tastiera non va: bash 2-TASTIERA-TEST-E-FIX.sh" ;;
esac

log "--- 6. Aggiornamenti"
log "Consigliato subito dopo:  sudo dnf upgrade --refresh   (porta un kernel piu' recente del 7.2.11 della ISO,"
log "con correzioni per questo portatile). Poi riavvia."
sync
popup "Dopo-installazione completato: riavvia il portatile" 10
