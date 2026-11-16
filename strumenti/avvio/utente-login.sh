#!/bin/bash
# Avviato da solo all'accesso di ogni utente: rende predefinita l'uscita "Altoparlanti potenziati".
grep -q 'Yoga-Slim7x' /proc/asound/cards 2>/dev/null || sleep 20
trova() { pw-cli ls Node 2>/dev/null | awk '/^\tid /{id=$2} /node.name = "effect_input.yoga_spk"/{print id}' | tr -d ,; }
ID=""
for i in $(seq 1 45); do
    ID=$(trova)
    if [ -n "$ID" ]; then break; fi
    if [ "$i" = 8 ] || [ "$i" = 25 ]; then systemctl --user restart filter-chain.service 2>/dev/null; fi
    sleep 2
done
if [ -n "$ID" ]; then wpctl set-default "$ID"; fi
exit 0
