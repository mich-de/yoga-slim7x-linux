#!/bin/bash
# Funzioni condivise dagli strumenti (Lenovo Yoga Slim 7x, Snapdragon X Elite).
# Si carica con:  . "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
# FAT32 non ha il bit "eseguibile": gli script si lanciano sempre con  bash NOME.sh

SELF=$(readlink -f "$0")
KIT=$(dirname "$SELF")
case "$KIT" in */avvio) KIT=$(dirname "$KIT") ;; esac
AUTO=0
for _a in "$@"; do [ "$_a" = --auto ] && AUTO=1; done

ts() { date +%Y%m%d-%H%M%S; }
is_live() { grep -qE 'rd\.live\.image|root=live:' /proc/cmdline; }
modello() { [ -r /proc/device-tree/model ] && tr -d '\0' < /proc/device-tree/model; }

# cartella dei log: sulla chiavetta se scrivibile, altrimenti in /tmp
logdir() {
    if mkdir -p "$KIT/log" 2>/dev/null && [ -w "$KIT/log" ]; then echo "$KIT/log"
    else mkdir -p /tmp/strumenti-log; echo /tmp/strumenti-log; fi
}

# utente della sessione grafica (liveuser nella live)
utente() {
    local u=${SUDO_USER:-} d
    if [ -z "$u" ] || [ "$u" = root ]; then
        u=""
        for d in /run/user/*; do
            [ -S "$d/wayland-0" ] || [ -S "$d/bus" ] || continue
            [ "${d##*/}" = 0 ] && continue
            u=$(id -nu "${d##*/}" 2>/dev/null) && break
        done
    fi
    [ -n "$u" ] || u=$(id -nu)
    echo "$u"
}

# esegue un comando come utente della sessione grafica (per kdialog, wpctl, pw-play...)
come_utente() {
    local u uid
    u=$(utente); uid=$(id -u "$u" 2>/dev/null) || return 1
    if [ "$(id -u)" -eq "$uid" ]; then "$@"; return; fi
    sudo -u "$u" env XDG_RUNTIME_DIR="/run/user/$uid" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" DISPLAY="${DISPLAY:-:0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# avviso a schermo che non blocca (e riga nel terminale)
popup() {
    echo ">>> $1"
    if [ "$AUTO" = 0 ] && command -v kdialog >/dev/null 2>&1; then
        come_utente kdialog --title "Strumenti" --passivepopup "$1" "${2:-8}" >/dev/null 2>&1 &
    fi
}

# domanda si/no grafica: 0 = si, 1 = no, 2 = impossibile chiedere
chiedi() {
    [ "$AUTO" = 1 ] && return 2
    command -v kdialog >/dev/null 2>&1 || return 2
    come_utente kdialog --title "Strumenti" --yesno "$1" 2>/dev/null
    case $? in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}

# se lanciato con doppio clic (senza terminale) si riapre dentro Konsole
apri_terminale() {
    [ "$AUTO" = 1 ] && return 0
    [ -t 1 ] && return 0
    command -v konsole >/dev/null 2>&1 && exec konsole --hold -e bash "$SELF" "$@"
    return 0
}

diventa_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    exec sudo -E bash "$SELF" "$@"
}

# ---- tastiera interna (controller ITE 048D:8987, I2C indirizzo 0x3a) ----------------

kbd_i2c() { ls -d /sys/bus/i2c/devices/*-003a 2>/dev/null | head -n1; }

# percorso /sys del dispositivo HID figlio del dispositivo I2C della tastiera
kbd_hid() {
    local i; i=$(kbd_i2c); [ -n "$i" ] || return 1
    ls -d "$i"/0018:*.* 2>/dev/null | head -n1
}

kbd_hid_driver() {
    local h; h=$(kbd_hid) || return 1
    [ -n "$h" ] && [ -L "$h/driver" ] && basename "$(readlink "$h/driver")"
}

# /dev/input/eventN della tastiera interna (blocco di /proc/bus/input/devices con "Keyboard" e bus 0018)
kbd_event() {
    awk 'BEGIN{RS=""} /Bus=0018/ && /Name="[^"]*[Kk]eyboard/ && /Handlers=[^\n]*kbd/ {
            if (match($0, /event[0-9]+/)) { print "/dev/input/" substr($0, RSTART, RLENGTH); exit } }' \
        "${1:-/proc/bus/input/devices}"
}

irq_hid() { grep -E 'hid-over-i2c|i2c_hid' "${1:-/proc/interrupts}" 2>/dev/null; }
# somma i contatori per CPU di ogni riga IRQ letta da stdin -> "gpio=conteggio,..." (gpio 67 = tastiera, 3 = touchpad, 51 = touchscreen)
irq_somma() { awk '{s=0; for(i=2;i<=NF;i++){ if ($i ~ /^[0-9]+$/) s+=$i; else break } printf "%s%s=%s", (NR>1?",":""), $(i+1), s}'; }

# misura per N secondi: byte di eventi letti dalla tastiera e variazione dei contatori IRQ.
# stampa una riga "eventi=<byte> irq_prima=... irq_dopo=..." ; ritorna 0 se sono arrivati eventi
misura_tastiera() {
    local sec=${1:-8} ev bytes=0 a b
    ev=$(kbd_event)
    a=$(irq_hid | irq_somma)
    if [ -n "$ev" ] && [ -r "$ev" ]; then
        bytes=$(timeout "$sec" cat "$ev" 2>/dev/null | wc -c)
    else
        sleep "$sec"
    fi
    b=$(irq_hid | irq_somma)
    echo "input=${ev:-nessuno} eventi_byte=$bytes irq_prima=[$a] irq_dopo=[$b]"
    [ "${bytes:-0}" -gt 0 ]
}

stato_tastiera() {
    local i h
    i=$(kbd_i2c); h=$(kbd_hid 2>/dev/null)
    echo "i2c=${i:-ASSENTE} driver_i2c=$( [ -n "$i" ] && [ -L "$i/driver" ] && basename "$(readlink "$i/driver")" || echo nessuno)"
    echo "hid=${h:-ASSENTE} driver_hid=$(kbd_hid_driver 2>/dev/null || echo nessuno)"
    echo "input=$(kbd_event)"
    echo "moduli: $(lsmod | awk '$1 ~ /^(hid_lenovo|i2c_hid|i2c_hid_of|hid_generic|hid_multitouch)$/ {printf "%s ", $1}')"
}

# stacca e riattacca il dispositivo I2C della tastiera (nuova inizializzazione del controller)
rebind_tastiera() {
    local i n d
    i=$(kbd_i2c); [ -n "$i" ] || { echo "dispositivo I2C 0x3a non trovato"; return 1; }
    n=$(basename "$i")
    if [ -L "$i/driver" ]; then
        d=$(readlink -f "$i/driver")
        echo "$n" > "$d/unbind" 2>/dev/null; sleep 1
    else
        d=$(ls -d /sys/bus/i2c/drivers/i2c_hid_of 2>/dev/null | head -n1)
    fi
    [ -n "$d" ] || { echo "driver i2c_hid_of non trovato"; return 1; }
    echo "$n" > "$d/bind" 2>/dev/null; sleep 3
    [ -L "$i/driver" ]
}
