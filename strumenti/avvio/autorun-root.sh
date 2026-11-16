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
sleep 40   # lascia partire il desktop e i driver
bash "$KIT/1-DIAGNOSTICA.sh" --auto > /dev/null
echo "diagnostica fatta $(date)"
sync
