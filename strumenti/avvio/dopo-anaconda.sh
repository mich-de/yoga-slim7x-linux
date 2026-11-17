#!/bin/bash
# Eseguito DA SOLO dal programma di installazione di Fedora a fine installazione (post-script iniettato in
# /usr/share/anaconda/post-scripts). Prepara il sistema appena installato senza che l'utente faccia nulla:
# tastiera (kernel corretto + aggancio per i kernel futuri), audio, firmware, passi della guida Fedora.
#   uso: dopo-anaconda.sh /mnt/sysroot
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
R=${1:-/mnt/sysroot}
if [ ! -d "$R/etc" ] || [ ! -d "$R/usr" ]; then echo "sistema installato non trovato in $R"; exit 0; fi
mkdir -p "$KIT/log" "$R/var/log"
L="$R/var/log/yoga-slim7x-installazione.log"
L2="$KIT/log/dopo-anaconda-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee -a "$L" "$L2") 2>&1
echo "=== dopo-anaconda $(date) - destinazione $R"

echo "--- 1. copia del kit in /opt/yoga-slim7x"
D="$R/opt/yoga-slim7x"; mkdir -p "$D/audio"
for x in LEGGIMI.txt HANDOFF.md avvio lib tools audio-auto firmware fix-tastiera ucm docs secureboot upstream; do
    if [ -e "$KIT/$x" ]; then cp -r "$KIT/$x" "$D/"; fi
done
cp "$KIT"/*.sh "$D/" 2>/dev/null
for f in "$KIT"/audio/*; do
    if [ -f "$f" ]; then cp "$f" "$D/audio/"; fi
done
echo "  copiati $(find "$D" -type f | wc -l) file"

echo "--- 2. tastiera e touchpad: kernel corretto + aggancio per i kernel futuri"
bash "$KIT/12-TASTIERA-FIX-PERMANENTE.sh" --auto --sistema "$R" 2>&1 | tail -n 8

echo "--- 3. audio"
bash "$KIT/avvio/audio-sistema.sh" "$R"
bash "$KIT/avvio/audio-yoga.sh" "$R"
mkdir -p "$R/etc/systemd/system/multi-user.target.d" "$R/etc/xdg/autostart"
printf '%s\n' '[Unit]' 'Description=Yoga Slim 7x: guadagno degli amplificatori degli altoparlanti' 'After=sound.target multi-user.target' '' \
    '[Service]' 'Type=oneshot' 'ExecStart=/bin/bash /opt/yoga-slim7x/avvio/audio-ampli.sh' '' \
    '[Install]' 'WantedBy=multi-user.target' > "$R/etc/systemd/system/yoga-audio-ampli.service"
# drop-in invece del collegamento in *.wants: al primo avvio systemd applica i preset e toglierebbe il collegamento
printf '%s\n' '[Unit]' 'Wants=yoga-audio-ampli.service' > "$R/etc/systemd/system/multi-user.target.d/10-yoga-audio.conf"
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Yoga Slim 7x - audio' \
    'Exec=/bin/bash /opt/yoga-slim7x/avvio/utente-login.sh' 'NoDisplay=true' > "$R/etc/xdg/autostart/yoga-audio.desktop"
echo "  servizio degli amplificatori e avvio automatico per gli utenti installati"

echo "--- 4. firmware"
PREFISSO="$R" bash "$KIT/8-INSTALLA-FIRMWARE.sh" --auto --forza 2>&1 | tail -n 4
mkdir -p "$R/etc/dracut.conf.d"
printf '%s\n' \
    'install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.mbn* "' \
    'install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.elf* "' \
    'install_items+=" /lib/firmware/updates/qcom/x1*/*/*/*.jsn* "' \
    'install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.mbn* "' \
    'install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.elf* "' \
    'install_items+=" /lib/firmware/qcom/x1e80100/LENOVO/83ED/*.jsn* "' > "$R/etc/dracut.conf.d/qcom-x1e-firmware.conf"

echo "--- 5. passi della guida Fedora"
rm -f "$R/etc/modprobe.d/anaconda-denylist.conf"
mkdir -p "$R/etc/modules-load.d"; echo scmi-cpufreq > "$R/etc/modules-load.d/scmi-cpufreq.conf"
if [ -x "$R/usr/bin/grubby" ] || [ -x "$R/usr/sbin/grubby" ]; then
    chroot "$R" grubby --update-kernel=ALL --args="systemd.tpm2_wait=0 clk_ignore_unused pd_ignore_unused" && echo "  parametri del kernel aggiunti"
    chroot "$R" grubby --update-kernel=ALL --remove-args="modprobe.blacklist=qcom_q6v5_pas module_blacklist=qcom_q6v5_pas enforcing=0"
    chroot "$R" grubby --info=DEFAULT 2>/dev/null | grep -E '^(kernel|args)'
    if [ -n "${YOGA_SALTA_DRACUT:-}" ]; then
        echo "  rigenerazione dell'initramfs saltata (YOGA_SALTA_DRACUT)"
    else
        echo "  rigenero l'initramfs (qualche minuto)..."
        if timeout 1200 chroot "$R" dracut --regenerate-all --force >/dev/null 2>&1; then echo "  initramfs rigenerato"; else echo "  ATTENZIONE: dracut ha dato errore o ha superato i 20 minuti"; fi
    fi
    chroot "$R" restorecon -R /opt/yoga-slim7x /etc/pipewire /etc/wireplumber /etc/systemd /etc/kernel /usr/local/sbin /usr/lib64/ladspa /usr/lib/firmware/updates /etc/dracut.conf.d /etc/modules-load.d /etc/xdg/autostart 2>/dev/null && echo "  etichette SELinux sistemate"
else
    echo "  grubby non trovato nel sistema installato: parametri e initramfs da fare al primo avvio (10-DOPO-INSTALLAZIONE-FEDORA.sh)"
fi
sync
echo "=== fine dopo-anaconda $(date)"
exit 0
