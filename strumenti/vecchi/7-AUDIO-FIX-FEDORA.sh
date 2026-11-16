#!/bin/bash
# Sistema l'audio (altoparlanti e microfoni interni) su Fedora INSTALLATA sul Yoga Slim 7x.
# Funziona anche su altre distro con systemd; i passi specifici di Fedora vengono saltati se non applicabili.
# Cosa serve all'audio su questo portatile:
#   1. il driver del coprocessore ADSP (qcom_q6v5_pas) NON disattivato (l'installer lo lascia in blacklist)
#   2. i firmware ADSP in /lib/firmware e dentro l'initramfs
#   3. la topologia audio X1E80100-LENOVO-Yoga-Slim7x-tplg.bin e il profilo ALSA UCM "Slim7x"
#   4. PipeWire + WirePlumber
# Nella sessione live usa invece 5-AUDIO-TEST-LIVE.sh.
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/audio-fix-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
RIAVVIO=0
U=/usr/share/alsa/ucm2

log "=== Audio fix $(date) - $(modello) - kernel $(uname -r)"
if is_live; then log "Questa e' la sessione live: usa 5-AUDIO-TEST-LIVE.sh (avvio 'live in RAM')."; exit 1; fi

log "--- 1. Driver ADSP"
for f in /etc/modprobe.d/*.conf; do
    [ -f "$f" ] || continue
    grep -q 'qcom_q6v5_pas' "$f" || continue
    if [ "$(basename "$f")" = anaconda-denylist.conf ]; then rm -f "$f"; log "rimosso $f"
    else sed -i '/qcom_q6v5_pas/s/^/# /' "$f"; log "commentata la riga qcom_q6v5_pas in $f"; fi
    RIAVVIO=1
done
if grep -qE '(modprobe\.|module_)blacklist=[^ ]*qcom_q6v5_pas' /proc/cmdline; then
    if command -v grubby >/dev/null; then
        grubby --update-kernel=ALL --remove-args="modprobe.blacklist=qcom_q6v5_pas module_blacklist=qcom_q6v5_pas" && log "tolta la blacklist dai parametri del kernel"
    else log "ATTENZIONE: togli a mano 'modprobe.blacklist=qcom_q6v5_pas' dai parametri del kernel (bootloader)"; fi
    RIAVVIO=1
fi

log "--- 2. Firmware"
bash "$KIT/8-INSTALLA-FIRMWARE.sh" --auto 2>&1 | tee -a "$L"

log "--- 3. Profilo ALSA UCM"
if [ ! -f "$U/Qualcomm/x1e80100/Slim7x-HiFi.conf" ]; then
    command -v dnf >/dev/null && dnf -y install alsa-ucm >> "$L" 2>&1
fi
if [ ! -f "$U/Qualcomm/x1e80100/Slim7x-HiFi.conf" ] && [ -f "$KIT/ucm/alsa-ucm-conf-master.tar.gz" ]; then
    t=$(mktemp -d); tar -xzf "$KIT/ucm/alsa-ucm-conf-master.tar.gz" -C "$t"
    mkdir -p "$U"; cp -rn "$t"/*/ucm2/. "$U"/ && log "profili UCM mancanti aggiunti dal kit (senza sovrascrivere quelli esistenti)"
    rm -rf "$t"
fi
[ -f "$U/Qualcomm/x1e80100/Slim7x-HiFi.conf" ] && log "profilo Slim7x presente" || log "ATTENZIONE: profilo Slim7x ancora assente"

log "--- 4. Pacchetti audio"
if command -v rpm >/dev/null; then
    for p in pipewire wireplumber pipewire-pulseaudio alsa-utils; do
        rpm -q "$p" >/dev/null 2>&1 || { log "manca $p: provo a installarlo"; dnf -y install "$p" >> "$L" 2>&1 || log "  non installato (serve la rete)"; }
    done
fi

log "--- 5. Avvio del coprocessore ADSP"
if grep -qE 'blacklist=[^ ]*qcom_q6v5_pas' /proc/cmdline; then
    log "il kernel in esecuzione ha ancora la blacklist: l'audio partira' dopo il riavvio"
else
    modprobe qcom_q6v5_pas 2>> "$L"; sleep 3
    for r in /sys/class/remoteproc/remoteproc*; do
        [ -d "$r" ] || continue
        n=$(cat "$r/name" 2>/dev/null); s=$(cat "$r/state" 2>/dev/null)
        if [ "$s" = offline ]; then echo start > "$r/state" 2>> "$L"; sleep 2; s=$(cat "$r/state" 2>/dev/null); fi
        log "remoteproc $n: $s"
    done
    for i in $(seq 1 20); do grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null && break; sleep 2; done
fi

log "--- 6. Stato"
cat /proc/asound/cards 2>&1 | tee -a "$L"
if grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null; then
    come_utente systemctl --user restart wireplumber pipewire pipewire-pulse >> "$L" 2>&1; sleep 4
    come_utente wpctl status 2>&1 | sed -n '1,40p' >> "$L"
    come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.40 >> "$L" 2>&1
    popup "Prova audio: tra poco un suono dagli altoparlanti" 4
    s=$(ls /usr/share/sounds/freedesktop/stereo/bell.oga /usr/share/sounds/ocean/stereo/bell.oga 2>/dev/null | head -n1)
    if [ -n "$s" ] && command -v pw-play >/dev/null; then come_utente pw-play "$s" >> "$L" 2>&1; sleep 1; come_utente pw-play "$s" >> "$L" 2>&1
    else come_utente speaker-test -t sine -f 440 -c 2 -l 1 >> "$L" 2>&1; fi
    chiedi "Hai sentito il suono dagli altoparlanti?"; case $? in 0) log "RISULTATO: audio FUNZIONANTE (confermato)";; 1) log "RISULTATO: scheda audio presente ma nessun suono udito";; *) log "RISULTATO: scheda audio presente, prova sonora eseguita";; esac
else
    log "RISULTATO: scheda audio non ancora presente."
fi
[ "$RIAVVIO" = 1 ] && log "RIAVVIA il portatile e, se l'audio non c'e' ancora, riesegui questo script."
log "Nota (wiki Fedora): la protezione degli altoparlanti potrebbe mancare: evita il volume al massimo per periodi lunghi."
sync
