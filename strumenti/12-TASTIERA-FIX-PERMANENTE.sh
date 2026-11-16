#!/bin/bash
# Rende permanente su Fedora INSTALLATA la correzione di tastiera e touchpad del Yoga Slim 7x
# (bus I2C b80000 a 100 kHz), correggendo il device tree dentro i kernel in /boot e installando
# un aggancio che ripete la correzione a ogni nuovo kernel.
#
#   Dal sistema installato:   sudo bash 12-TASTIERA-FIX-PERMANENTE.sh
#   Dalla live, subito dopo l'installazione e PRIMA di riavviare (cosi' la tastiera va gia' al primo avvio):
#                             sudo bash 12-TASTIERA-FIX-PERMANENTE.sh --dalla-live
#   Con un sistema montato a mano:  sudo bash 12-TASTIERA-FIX-PERMANENTE.sh --sistema /mnt/radice [--boot /mnt/boot]
#
# LIMITE: un kernel modificato non ha piu' la firma valida, quindi NON parte con Secure Boot attivo.
# Con Secure Boot attivo la correzione deve arrivare dal kernel ufficiale (segnalazione in upstream/).
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/tastiera-permanente-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
PATCH="$KIT/tools/patch-dtb-i2c100k.py"
ROOT=""; BOOT=""; LIVE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --sistema) ROOT=$2; shift ;;
        --boot) BOOT=$2; shift ;;
        --dalla-live) LIVE=1 ;;
    esac
    shift
done
MONTATI=""
smonta() { for m in $MONTATI; do umount "$m" 2>/dev/null; done; }
trap smonta EXIT

log "=== Fix tastiera permanente $(date) - kernel in esecuzione $(uname -r)"
command -v python3 >/dev/null || { log "python3 non trovato"; exit 1; }
[ -f "$PATCH" ] || { log "manca $PATCH"; exit 1; }

if [ "$LIVE" = 1 ]; then
    # cerca le partizioni Linux del disco interno: quella con vmlinuz-* e' /boot, quella con etc/os-release e' la radice
    for p in $(lsblk -lnpo NAME,FSTYPE | awk '$1 ~ /nvme/ && $2 ~ /^(ext4|xfs|btrfs)$/ {print $1}'); do
        m=$(mktemp -d /run/yoga-mnt.XXXX)
        mount "$p" "$m" 2>/dev/null || { rmdir "$m"; continue; }
        MONTATI="$m $MONTATI"
        ls "$m"/vmlinuz-* >/dev/null 2>&1 && BOOT=$m
        for r in "$m" "$m/root" "$m/@"; do [ -f "$r/etc/os-release" ] && [ -d "$r/usr/lib/modules" ] && ROOT=$r; done
        log "trovata $p: $(ls "$m" | head -n 8 | tr '\n' ' ')"
    done
    [ -n "$BOOT" ] || [ -n "$ROOT" ] || { log "Nessuna installazione Linux trovata sul disco interno."; exit 1; }
elif [ -z "$ROOT" ]; then
    if is_live; then log "Sessione live: usa --dalla-live (dopo aver installato) oppure la voce GRUB 'FIX TASTIERA'."; exit 1; fi
    ROOT=/
fi
[ -n "$BOOT" ] || BOOT="${ROOT%/}/boot"
log "radice: ${ROOT:-non trovata}   boot: $BOOT"

if [ "$ROOT" = / ] && command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    log "Secure Boot e' ATTIVO: un kernel modificato non partirebbe. Non applico nulla."
    exit 1
fi

n=0
for f in "$BOOT"/vmlinuz-* "$BOOT"/dtb-*/qcom/x1e80100-lenovo-yoga-slim7x.dtb "${ROOT%/}"/usr/lib/modules/*/dtb/qcom/x1e80100-lenovo-yoga-slim7x.dtb; do
    [ -f "$f" ] || continue
    case "$f" in *.orig|*rescue*) continue ;; esac
    out=$(python3 "$PATCH" "$f" --in-place 2>&1); rc=$?
    log "$f: rc=$rc $(echo "$out" | tail -n 1)"
    [ $rc -eq 0 ] && n=$((n + 1))
    rm -f "$f.orig"
done
log "file controllati/corretti: $n   (il kernel 'rescue' resta originale come riserva)"

if [ -n "$ROOT" ] && [ -d "${ROOT%/}/etc" ]; then
    mkdir -p "${ROOT%/}/usr/local/sbin" "${ROOT%/}/etc/kernel/install.d"
    install -m 0755 "$PATCH" "${ROOT%/}/usr/local/sbin/yoga-patch-dtb-i2c100k"
    cat > "${ROOT%/}/etc/kernel/install.d/99-yoga-kbd100k.install" <<'EOF'
#!/bin/sh
# Yoga Slim 7x: dopo l'installazione di un kernel porta a 100 kHz il bus I2C di tastiera e touchpad
# nel device tree incorporato in /boot/vmlinuz-<versione> e nei .dtb separati.
# Installato da STRUMENTI/12-TASTIERA-FIX-PERMANENTE.sh. Per toglierlo: cancella questo file.
[ "$1" = add ] || exit 0
KVER="$2"
for f in "/boot/vmlinuz-$KVER" "/boot/dtb-$KVER/qcom/x1e80100-lenovo-yoga-slim7x.dtb" "/usr/lib/modules/$KVER/dtb/qcom/x1e80100-lenovo-yoga-slim7x.dtb"; do
    [ -f "$f" ] && /usr/bin/python3 /usr/local/sbin/yoga-patch-dtb-i2c100k "$f" --in-place && rm -f "$f.orig"
done
exit 0
EOF
    chmod 0755 "${ROOT%/}/etc/kernel/install.d/99-yoga-kbd100k.install"
    [ "$ROOT" = / ] && command -v restorecon >/dev/null && restorecon /usr/local/sbin/yoga-patch-dtb-i2c100k /etc/kernel/install.d/99-yoga-kbd100k.install
    log "installato l'aggancio per i prossimi kernel: /etc/kernel/install.d/99-yoga-kbd100k.install"
else
    log "radice del sistema non trovata: corretti solo i kernel. Dal sistema installato riesegui questo script per installare l'aggancio."
fi
sync
log "Fatto. Al prossimo avvio tastiera e touchpad devono funzionare subito."
log "Se un domani il kernel ufficiale includera' la correzione, togli /etc/kernel/install.d/99-yoga-kbd100k.install."
