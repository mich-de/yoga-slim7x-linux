#!/bin/bash
# Installa i firmware Qualcomm del Yoga Slim 7x (estratti dal Windows di QUESTO portatile) su qualsiasi distro.
# Servono a: audio e batteria (ADSP), NPU/sensori (CDSP), GPU (zap shader), decodifica video.
# Destinazione: /usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED  (la cartella "updates" ha la precedenza
# su quella della distro). Poi rigenera l'initramfs (dracut, initramfs-tools o mkinitcpio).
#   bash 8-INSTALLA-FIRMWARE.sh [--auto] [--forza]
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/firmware-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
FORZA=0; for a in "$@"; do [ "$a" = --forza ] && FORZA=1; done
P=qcom/x1e80100/LENOVO/83ED
T=X1E80100-LENOVO-Yoga-Slim7x-tplg.bin
SRC="$KIT/firmware"
# PREFISSO=/mnt/sistema bash 8-INSTALLA-FIRMWARE.sh --forza  -> installa dentro un sistema montato altrove
# (in quel caso l'initramfs non viene rigenerato: fallo dal sistema stesso)
PREFISSO=${PREFISSO:-}
BASE="$PREFISSO/usr/lib/firmware"; [ -d "$BASE" ] || BASE="$PREFISSO/lib/firmware"
DST="$BASE/updates"

m=$(modello)
log "=== Installazione firmware $(date) - modello: ${m:-sconosciuto} - $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
if [ "$m" != "Lenovo Yoga Slim 7x" ] && [ "$FORZA" = 0 ]; then
    log "Questo kit e' per il 'Lenovo Yoga Slim 7x'. Modello rilevato: '${m}'. Usa --forza solo se sai cosa fai."
    exit 1
fi
[ -d "$SRC/$P" ] || { log "Cartella firmware non trovata: $SRC/$P"; exit 1; }

esiste() { ls "$BASE/$1" "$BASE/$1.xz" "$BASE/$1.zst" "$DST/$1" "$DST/$1.xz" "$DST/$1.zst" 2>/dev/null | head -n1; }

mkdir -p "$DST/$P"
for f in "$SRC/$P"/*; do
    n=$(basename "$f")
    [ "$n" = "$T" ] && continue
    rm -f "$DST/$P/$n.xz" "$DST/$P/$n.zst"
    install -m 0644 "$f" "$DST/$P/$n" && log "installato $DST/$P/$n"
done
# topologia audio: solo se la distro non la fornisce gia' (quella della distro e' allineata al suo kernel)
if [ -z "$(esiste "$P/$T")" ] && [ -f "$SRC/$P/$T" ]; then
    install -m 0644 "$SRC/$P/$T" "$DST/$P/$T" && log "installata topologia audio $DST/$P/$T"
fi
if [ -z "$(esiste "qcom/x1e80100/$T")" ]; then
    mkdir -p "$DST/qcom/x1e80100"; ln -sf "LENOVO/83ED/$T" "$DST/qcom/x1e80100/$T"
    # il collegamento deve puntare a un file esistente accanto: se la topologia e' della distro, copiala
    [ -e "$DST/$P/$T" ] || { t=$(esiste "$P/$T"); [ -n "$t" ] && cp "$t" "$DST/$P/"; }
    log "creato collegamento qcom/x1e80100/$T"
fi
# firmware generici della GPU Adreno (da linux-firmware): solo se la distro non li ha
for g in qcom/gen70500_sqe.fw qcom/gen70500_gmu.bin qcom/x1e80100/gen70500_zap.mbn; do
    if [ -z "$(esiste "$g")" ] && [ -f "$SRC/$g" ]; then
        mkdir -p "$DST/$(dirname "$g")"; install -m 0644 "$SRC/$g" "$DST/$g" && log "installato $DST/$g (mancava nella distro)"
    fi
done
if [ -z "$PREFISSO" ] && command -v restorecon >/dev/null; then restorecon -R "$DST/qcom" 2>/dev/null; fi

if [ -n "$PREFISSO" ]; then
    log "Installato in $PREFISSO: rigenera l'initramfs dal sistema di destinazione."
elif is_live; then
    log "Sessione live: firmware copiati, initramfs non toccato."
else
    if command -v dracut >/dev/null; then
        cat > /etc/dracut.conf.d/qcom-x1e-firmware.conf <<'EOF'
# Firmware dei coprocessori Qualcomm nell'initramfs (wiki Fedora: Snapdragon_WoA_Laptop_Install)
install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.mbn* "
install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.elf* "
install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.jsn* "
install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.mbn* "
install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.elf* "
install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.jsn* "
EOF
        log "Rigenero l'initramfs con dracut (puo' richiedere qualche minuto)..."
        dracut --regenerate-all --force >> "$L" 2>&1 && log "initramfs rigenerato" || log "ATTENZIONE: dracut ha dato errore (vedi $L)"
    elif command -v update-initramfs >/dev/null; then
        cat > /etc/initramfs-tools/hooks/qcom-x1e-firmware <<'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
for f in /lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/* /lib/firmware/qcom/x1e80100/LENOVO/83ED/*; do
    [ -e "$f" ] && copy_file firmware "$f"
done
exit 0
EOF
        chmod 755 /etc/initramfs-tools/hooks/qcom-x1e-firmware
        log "Rigenero l'initramfs con update-initramfs..."
        update-initramfs -u -k all >> "$L" 2>&1 && log "initramfs rigenerato" || log "ATTENZIONE: update-initramfs ha dato errore"
    elif command -v mkinitcpio >/dev/null; then
        mkdir -p /etc/mkinitcpio.conf.d
        echo "FILES+=($DST/$P/*)" > /etc/mkinitcpio.conf.d/qcom-x1e-firmware.conf
        log "Rigenero l'initramfs con mkinitcpio..."
        mkinitcpio -P >> "$L" 2>&1 && log "initramfs rigenerato" || log "ATTENZIONE: mkinitcpio ha dato errore"
    else
        log "Generatore di initramfs non riconosciuto: includi a mano i file di $DST/$P nell'initramfs."
    fi
fi
ls -la "$DST/$P" >> "$L" 2>&1
sync
log "Fatto. Riavvia per caricare i nuovi firmware."
