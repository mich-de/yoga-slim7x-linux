#!/bin/bash
# Eseguito come root all'avvio della live (servizio strumenti.service, iniettato da strumenti.cpio).
# Fa tutto da solo e senza rete: audio (uscita potenziata + guadagno degli amplificatori) e diagnostica in log/.
# Non deve mai bloccare l'avvio.
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
mkdir -p "$KIT/log"
exec >> "$KIT/log/autorun.log" 2>&1
echo "=== autorun $(date) - kernel $(uname -r) - cmdline: $(cat /proc/cmdline)"
bash "$KIT/avvio/audio-sistema.sh"
touch /run/yoga-audio-pronto
# se l'utente e' gia' entrato, fa rileggere le configurazioni ai suoi servizi audio
for d in /run/user/*; do
    [ -d "$d" ] || continue
    [ "${d##*/}" = 0 ] && continue
    u=$(id -nu "${d##*/}" 2>/dev/null) || continue
    sudo -u "$u" XDG_RUNTIME_DIR="$d" systemctl --user restart wireplumber filter-chain 2>/dev/null
done
bash "$KIT/avvio/audio-ampli.sh"
# Windows cifra C: e D: tenendo la chiave in chiaro sul disco (BitLocker "in attesa di attivazione"):
# cryptsetup li apre senza password e in Dolphin compaiono come dischi normali. Il timeout evita blocchi.
# shortcut: vale solo per la live; su Fedora installata serve una voce in /etc/crypttab, da aggiungere con l'installazione.
for d in $(blkid -t TYPE=BitLocker -o device 2>/dev/null); do
    n="win-${d##*/}"
    [ -e "/dev/mapper/$n" ] || echo x | timeout 30 cryptsetup open --type bitlk --key-file - "$d" "$n"
    echo "BitLocker $d -> /dev/mapper/$n: $([ -e "/dev/mapper/$n" ] && echo aperto || echo NON aperto)"
done
sleep 40  # lascia partire il desktop e i driver
bash "$KIT/1-DIAGNOSTICA.sh" --auto > /dev/null
echo "diagnostica fatta $(date)"
sync
