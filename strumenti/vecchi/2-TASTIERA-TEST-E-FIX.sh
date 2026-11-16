#!/bin/bash
# Tastiera interna del Yoga Slim 7x: misura se arrivano eventi e prova i rimedi noti, uno alla volta.
# Non serve scrivere nulla: quando compare l'avviso, premi alcuni tasti della tastiera INTERNA.
# Il risultato resta in log/tastiera-*.txt (da far leggere a Claude su Windows).
#   bash 2-TASTIERA-TEST-E-FIX.sh               prova tutto
#   bash 2-TASTIERA-TEST-E-FIX.sh --permanente  (sistema installato) rende fisso il rimedio che ha funzionato
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/tastiera-$(ts).txt"; ESITO="$LD/tastiera-ESITO.txt"
log() { echo "$*" | tee -a "$L"; }
SEC=8

prova() { # $1 = nome del passo ; ritorna 0 se la tastiera produce eventi
    local r
    popup "PREMI ORA alcuni tasti della tastiera interna ($SEC secondi) - prova: $1" "$SEC"
    r=$(misura_tastiera "$SEC"); local rc=$?
    log "[$1] $r"
    if [ $rc -eq 0 ]; then log "[$1] => la tastiera INVIA eventi"; else log "[$1] => nessun evento"; fi
    return $rc
}

permanente() { # $1 = rimedio
    is_live && { log "Sessione live: il rimedio permanente si applica dopo l'installazione."; return 1; }
    case "$1" in
        rebind)
            cat > /usr/local/sbin/yoga-tastiera-rebind <<'EOF'
#!/bin/sh
# Reinizializza il controller della tastiera interna (I2C 0x3a) all'avvio.
i=$(ls -d /sys/bus/i2c/devices/*-003a 2>/dev/null | head -n1); [ -n "$i" ] || exit 0
n=$(basename "$i"); d=$(readlink -f "$i/driver" 2>/dev/null); [ -n "$d" ] || d=/sys/bus/i2c/drivers/i2c_hid_of
echo "$n" > "$d/unbind" 2>/dev/null; sleep 1; echo "$n" > "$d/bind" 2>/dev/null; exit 0
EOF
            chmod 755 /usr/local/sbin/yoga-tastiera-rebind
            cat > /etc/systemd/system/yoga-tastiera-rebind.service <<'EOF'
[Unit]
Description=Reinizializza la tastiera interna del Yoga Slim 7x
After=systemd-modules-load.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/yoga-tastiera-rebind

[Install]
WantedBy=multi-user.target
EOF
            command -v restorecon >/dev/null && restorecon /usr/local/sbin/yoga-tastiera-rebind /etc/systemd/system/yoga-tastiera-rebind.service
            systemctl daemon-reload && systemctl enable yoga-tastiera-rebind.service
            log "Installato il servizio yoga-tastiera-rebind (attivo dal prossimo avvio)." ;;
        generic)
            if command -v grubby >/dev/null; then grubby --update-kernel=ALL --args="module_blacklist=hid_lenovo"
            else echo "blacklist hid_lenovo" > /etc/modprobe.d/yoga-tastiera.conf; fi
            log "Driver hid_lenovo escluso all'avvio (module_blacklist=hid_lenovo)." ;;
        *) log "Nessun rimedio permanente per '$1'."; return 1 ;;
    esac
}

log "=== Test tastiera $(date) - $(modello) - kernel $(uname -r)"
log "cmdline: $(cat /proc/cmdline)"
stato_tastiera | tee -a "$L"
irq_hid >> "$L"
dmesg | grep -iE 'i2c_hid|hid-over-i2c|048d|lenovo|0-003a' | tail -n 40 >> "$L"

if [ "$1" = --permanente ]; then
    r=$(sed -n 's/^RIMEDIO=//p' "$ESITO" 2>/dev/null | tail -n1)
    [ -n "$r" ] || { log "Nessun esito salvato: esegui prima il test senza opzioni."; exit 1; }
    permanente "$r"; sync; exit
fi

RIMEDIO=nessuno
if prova "0-stato-attuale"; then
    RIMEDIO=gia-funzionante
else
    log "--- Passo 1: reinizializzo il controller (unbind/bind del dispositivo I2C)"
    rebind_tastiera 2>&1 | tee -a "$L"; stato_tastiera >> "$L"
    if prova "1-rebind"; then RIMEDIO=rebind
    else
        log "--- Passo 2: tolgo il driver hid_lenovo e lascio la tastiera al driver generico"
        mkdir -p /run/modprobe.d; echo "blacklist hid_lenovo" > /run/modprobe.d/strumenti-tastiera.conf
        h=$(kbd_hid 2>/dev/null)
        [ -n "$h" ] && [ -L "$h/driver" ] && echo "$(basename "$h")" > "$(readlink -f "$h/driver")/unbind" 2>/dev/null
        modprobe -r hid_lenovo 2>&1 | tee -a "$L"
        rebind_tastiera 2>&1 | tee -a "$L"; stato_tastiera >> "$L"
        if prova "2-driver-generico"; then RIMEDIO=generic
        else
            log "--- Passo 3: ricarico hid_lenovo e reinizializzo ancora"
            rm -f /run/modprobe.d/strumenti-tastiera.conf; modprobe hid_lenovo 2>&1 | tee -a "$L"
            rebind_tastiera 2>&1 | tee -a "$L"; stato_tastiera >> "$L"
            prova "3-rebind-dopo-ricarica" && RIMEDIO=rebind
        fi
    fi
fi
dmesg | tail -n 60 >> "$L"
{ echo "DATA=$(date)"; echo "KERNEL=$(uname -r)"; echo "RIMEDIO=$RIMEDIO"; } > "$ESITO"
sync
echo
case "$RIMEDIO" in
    gia-funzionante) log "RISULTATO: la tastiera invia gia' eventi al kernel. Se nelle app non scrive, il problema e' nel desktop (vedi log diagnostica)." ;;
    rebind)  log "RISULTATO: FUNZIONA dopo la reinizializzazione. Dopo l'installazione: bash 2-TASTIERA-TEST-E-FIX.sh --permanente" ;;
    generic) log "RISULTATO: FUNZIONA con il driver generico. Avvio alternativo: voce GRUB 'senza hid_lenovo'. Dopo l'installazione: --permanente" ;;
    *)       log "RISULTATO: nessun rimedio ha funzionato. Prova 3-SOSPENSIONE-TEST.sh, poi riporta la chiavetta su Windows per l'analisi del log." ;;
esac
popup "Test tastiera finito: $RIMEDIO" 10
