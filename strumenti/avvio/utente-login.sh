#!/bin/bash
# Avviato da solo all'accesso di ogni utente: rende predefinita l'uscita "Audio Yoga" (profili audio) se c'e',
# altrimenti "Altoparlanti potenziati".
grep -q 'Yoga-Slim7x' /proc/asound/cards 2>/dev/null || sleep 20
trova() { pw-cli ls Node 2>/dev/null | awk -v n="node.name = \"$1\"" '/^\tid /{id=$2} index($0, n){print id}' | tr -d ,; }
ID=""
for i in $(seq 1 45); do
    S=$(trova effect_input.yoga_spk); Y=$(trova effect_input.audio_yoga)
    if [ -n "$Y" ] && [ -n "$S" ]; then ID=$Y; break; fi
    if [ -n "$S" ] && [ "$i" -ge 12 ]; then ID=$S; break; fi	# Audio Yoga non e' partito: resta l'uscita di prima
    if [ "$i" = 8 ] || [ "$i" = 25 ]; then systemctl --user restart filter-chain.service 2>/dev/null; fi
    sleep 2
done
if [ -n "$ID" ]; then wpctl set-default "$ID"; fi
exit 0
