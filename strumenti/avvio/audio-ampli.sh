#!/bin/bash
# Guadagno degli amplificatori degli altoparlanti, senza domande: stessa logica e stessi valori di
# 7-VOLUME-AMPLIFICATORI.sh (scelti il 16/11: woofer 18, tweeter 16, tetto 18). Eseguito come root a ogni avvio.
# In Linux non esiste la protezione degli altoparlanti di Windows: NON aumentare questi valori.
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
KV=$(uname -r)
for i in $(seq 1 60); do grep -q 'Yoga-Slim7x' /proc/asound/cards 2>/dev/null && break; sleep 2; done
C=$(awk '/Yoga-Slim7x/ {print $1; exit}' /proc/asound/cards 2>/dev/null)
if [ -z "$C" ]; then echo "audio-ampli: scheda audio del Yoga non presente, nulla da fare"; exit 0; fi
MOD=""; ST=/var/lib/yoga-slim7x
if [ "$KV" = 7.2.11-300.fc45.aarch64 ] && [ -f "$KIT/audio/wsagain.ko" ]; then MOD="$KIT/audio/wsagain.ko"; fi
if [ -f "$ST/wsagain-$KV.ko" ]; then MOD="$ST/wsagain-$KV.ko"; fi
if [ -z "$MOD" ] && [ -d "/usr/src/kernels/$KV" ] && command -v make >/dev/null && command -v gcc >/dev/null; then
    b=$(mktemp -d); cp "$KIT/audio/wsagain.c" "$KIT/audio/Makefile" "$b/"
    if make -C "/usr/src/kernels/$KV" M="$b" modules >/dev/null 2>&1; then
        mkdir -p "$ST"; cp "$b/wsagain.ko" "$ST/wsagain-$KV.ko"; MOD="$ST/wsagain-$KV.ko"; echo "audio-ampli: modulo ricompilato per $KV"
    fi
    rm -rf "$b"
fi
pa() {
    local id
    id=$(amixer -c "$C" controls | grep "name='$1 PA Volume'" | sed -E 's/numid=([0-9]+).*/\1/')
    if [ -n "$id" ]; then amixer -q -c "$C" cset numid="$id" "$2" && echo "  $1 PA Volume = $2"; fi
}
if [ -n "$MOD" ]; then
    lsmod | grep -q '^wsagain' && rmmod wsagain
    cp "$MOD" /run/wsagain.ko
    if insmod /run/wsagain.ko en=0 cap=18; then
        pa WooferLeft 18; pa WooferRight 18; pa TweeterLeft 16; pa TweeterRight 16
    else
        echo "audio-ampli: modulo non caricabile sul kernel $KV"
    fi
else
    echo "audio-ampli: nessun modulo wsagain per il kernel $KV (per ricompilarlo servono kernel-devel, gcc e make): guadagno invariato"
fi
for d in /sys/bus/soundwire/devices/sdw:*; do
    if [ -e "$d/power/control" ]; then echo on > "$d/power/control"; fi
done
exit 0
