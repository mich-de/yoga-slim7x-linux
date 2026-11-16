#!/bin/bash
# Installa SENZA RETE, nel sistema indicato (nessun argomento = sistema in esecuzione), l'audio del Yoga Slim 7x
# per tutti gli utenti: plugin LADSPA, uscita "Altoparlanti potenziati" (PipeWire filter-chain), regola WirePlumber.
# Usa i file di audio/ (configurazioni messe a punto il 16/11) e audio-auto/ladspa (plugin presi da Fedora 45).
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
R=${1:-}
metti() { mkdir -p "$(dirname "$2")" && install -m "${3:-0644}" "$1" "$2" && echo "  $2"; }
echo "audio-sistema: destinazione ${R:-/}"
for p in sc4_1882.so fast_lookahead_limiter_1913.so; do
    [ -f "$R/usr/lib64/ladspa/$p" ] || metti "$KIT/audio-auto/ladspa/$p" "$R/usr/lib64/ladspa/$p" 0755
done
metti "$KIT/audio/50-yoga-altoparlanti.conf" "$R/etc/pipewire/filter-chain.conf.d/50-yoga-altoparlanti.conf"
metti "$KIT/audio/51-yoga-soft-mixer.conf" "$R/etc/wireplumber/wireplumber.conf.d/51-yoga-soft-mixer.conf"
# attivazione per tutti gli utenti con un drop-in (i collegamenti in *.wants vengono tolti dai preset di systemd)
mkdir -p "$R/etc/systemd/user/default.target.d"
printf '%s\n' '[Unit]' 'Wants=filter-chain.service' > "$R/etc/systemd/user/default.target.d/10-yoga-audio.conf" && echo "  filter-chain attivo per tutti gli utenti"
if [ -z "$R" ] && command -v restorecon >/dev/null; then restorecon -R /usr/lib64/ladspa /etc/pipewire /etc/wireplumber /etc/systemd/user 2>/dev/null; fi
exit 0
