#!/bin/bash
# Sospende il portatile per 12 secondi e lo riprende, poi misura se la tastiera interna invia eventi.
# (Su un altro portatile X Elite la tastiera si sblocca proprio dopo una sospensione/ripresa.)
# Se non si riprende da solo: tieni premuto il tasto di accensione. Nella live non si perde nulla.
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/sospensione-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
log "=== Test sospensione $(date) - kernel $(uname -r) - mem_sleep: $(cat /sys/power/mem_sleep 2>/dev/null)"
stato_tastiera | tee -a "$L"
popup "Tra 5 secondi il portatile va in sospensione per 12 secondi" 5
sync; sleep 5
if command -v rtcwake >/dev/null && rtcwake -m freeze -s 12 >> "$L" 2>&1; then log "ripresa da rtcwake"
else log "rtcwake non riuscito: provo systemctl suspend (riaccendi tu col tasto di accensione)"; systemctl suspend; sleep 15; fi
sleep 4
stato_tastiera | tee -a "$L"
popup "PREMI ORA alcuni tasti della tastiera interna (8 secondi)" 8
if r=$(misura_tastiera 8); then log "$r"; log "RISULTATO: dopo la sospensione la tastiera INVIA eventi"; echo "RIMEDIO=sospensione" >> "$LD/tastiera-ESITO.txt"
else log "$r"; log "RISULTATO: nessun evento anche dopo la sospensione"; fi
dmesg | tail -n 80 >> "$L"; sync
