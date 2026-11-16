#!/bin/bash
# Prova l'audio (e la batteria) nella sessione LIVE, prima di installare.
# IMPORTANTE: avvia la chiavetta con la voce "live in RAM". Accendere il coprocessore ADSP resetta le porte
# USB-C: se il sistema live gira dalla chiavetta si blocca, se e' stato copiato in RAM non succede nulla.
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

R=/run/strumenti-ram; mkdir -p "$R"
L="$R/audio-live-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
salva_log() {
    local i dev
    for i in $(seq 1 20); do
        if [ -w "$KIT/log" ] && touch "$KIT/log/.prova" 2>/dev/null; then rm -f "$KIT/log/.prova"; cp "$L" "$KIT/log/" && sync && return 0; fi
        dev=$(blkid -c /dev/null -L STRUMENTI 2>/dev/null)
        if [ -n "$dev" ]; then umount -l "$KIT" 2>/dev/null; mkdir -p "$KIT"; mount -t vfat -o rw,umask=000,utf8 "$dev" "$KIT" 2>/dev/null && mkdir -p "$KIT/log"; fi
        sleep 3
    done
    echo "Log rimasto in $L (chiavetta non rimontata)"; return 1
}

log "=== Test audio live $(date) - $(modello) - kernel $(uname -r)"
log "cmdline: $(cat /proc/cmdline)"
if is_live && ! grep -q 'rd\.live\.ram' /proc/cmdline; then
    log "La live NON e' in RAM: riavvia e scegli la voce 'live in RAM (test audio e batteria)'. Test annullato."
    popup "Riavvia scegliendo la voce 'live in RAM': test audio annullato" 12
    cp "$L" "$(logdir)/" 2>/dev/null; exit 1
fi

log "--- 1. Copio firmware in RAM e li installo"
cp -r "$KIT/firmware" "$R/" 2>> "$L"
BASE=/usr/lib/firmware; [ -d "$BASE" ] || BASE=/lib/firmware
P=qcom/x1e80100/LENOVO/83ED
mkdir -p "$BASE/updates/$P"
for f in "$R/firmware/$P"/*; do
    n=$(basename "$f"); case "$n" in *-tplg.bin) continue ;; esac
    install -m 0644 "$f" "$BASE/updates/$P/$n"
done
command -v restorecon >/dev/null && restorecon -R "$BASE/updates" 2>/dev/null
ls "$BASE/updates/$P" >> "$L" 2>&1
sync

log "--- 2. Accendo il coprocessore ADSP (le porte USB-C si resettano per qualche secondo)"
modprobe qcom_q6v5_pas 2>> "$L"; sleep 5
for r in /sys/class/remoteproc/remoteproc*; do
    [ -d "$r" ] || continue
    s=$(cat "$r/state" 2>/dev/null)
    if [ "$s" = offline ]; then echo start > "$r/state" 2>> "$L"; sleep 3; s=$(cat "$r/state" 2>/dev/null); fi
    log "remoteproc $(cat "$r/name" 2>/dev/null): $s"
done

log "--- 3. Attendo la scheda audio (fino a 60 secondi)"
for i in $(seq 1 30); do grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null && break; sleep 2; done
cat /proc/asound/cards 2>&1 | tee -a "$L"
log "batteria: $(ls /sys/class/power_supply/ 2>/dev/null | tr '\n' ' ')"

if grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null; then
    come_utente systemctl --user restart wireplumber pipewire pipewire-pulse >> "$L" 2>&1; sleep 5
    come_utente wpctl status 2>&1 | sed -n '1,40p' >> "$L"
    come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40 >> "$L" 2>&1
    popup "Prova audio: tra poco un suono dagli altoparlanti" 4; sleep 2
    s=$(ls /usr/share/sounds/freedesktop/stereo/bell.oga /usr/share/sounds/ocean/stereo/bell.oga 2>/dev/null | head -n1)
    if [ -n "$s" ] && command -v pw-play >/dev/null; then come_utente pw-play "$s" >> "$L" 2>&1; sleep 1; come_utente pw-play "$s" >> "$L" 2>&1
    else come_utente speaker-test -t sine -f 440 -c 2 -l 1 >> "$L" 2>&1; fi
    chiedi "Hai sentito il suono dagli altoparlanti?"
    case $? in 0) log "RISULTATO: audio FUNZIONANTE nella live (confermato)" ;; 1) log "RISULTATO: scheda audio presente ma nessun suono udito" ;; *) log "RISULTATO: scheda audio presente, prova sonora eseguita" ;; esac
else
    log "RISULTATO: nessuna scheda audio. Ultime righe del kernel:"
    dmesg | grep -iE 'remoteproc|q6|audio|snd|tplg|firmware' | tail -n 40 >> "$L"
fi
dmesg | tail -n 80 >> "$L"
salva_log
popup "Test audio finito: log salvato sulla chiavetta" 8
